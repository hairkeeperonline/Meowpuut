// NAPI 桥：从 ArkTS 侧到 Rust 引擎（crates/meowpuut-ffi，见 meowpuut.h）。
// 和 Android 的 meowpuut_jni.c 一一对应，只是把 JNI 换成 node-api（NAPI）。
//
// 词典读取：ArkTS 侧用 resourceManager.getRawFileContentSync 把 rawfile 读成
// Uint8Array 传进来；这里用一个 napi_ref 把它的 ArrayBuffer 钉住，然后调用
// mpn_lexicon_create_from_base_in_place 原地读（不复制到堆）。释放回调 free 由
// 引擎负责（等价于 JNI 版的 unmap_asset）。字符串以 UTF-16 跨边界传递，
// 扩展 B 区及以后的汉字不会损坏（和 JNI 版一样）。

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "napi/native_api.h"

#include "meowpuut.h"

#define SESSION(handle) reinterpret_cast<MPNSession *>(static_cast<intptr_t>(handle))
#define LEXICON(handle) reinterpret_cast<MPNLexicon *>(static_cast<intptr_t>(handle))

namespace {

// ---------------------------------------------------------------------------
// 字符串转换：UTF-8 <-> UTF-16（NAPI 字符串是 UTF-16）
// ---------------------------------------------------------------------------

napi_value ToJS(napi_env env, const char *text) {
  if (text == nullptr) text = "";
  size_t bytes = strlen(text);
  std::vector<char16_t> out(bytes + 1, 0);
  size_t n = 0;
  const unsigned char *p = reinterpret_cast<const unsigned char *>(text);
  while (*p) {
    uint32_t c = *p++;
    int extra = 0;
    if (c < 0x80) {
      extra = 0;
    } else if ((c & 0xE0) == 0xC0) {
      c &= 0x1F; extra = 1;
    } else if ((c & 0xF0) == 0xE0) {
      c &= 0x0F; extra = 2;
    } else if ((c & 0xF8) == 0xF0) {
      c &= 0x07; extra = 3;
    } else {
      c = 0xFFFD;
    }
    for (int i = 0; i < extra; i++) {
      if ((*p & 0xC0) != 0x80) { c = 0xFFFD; break; }
      c = (c << 6) | (*p++ & 0x3F);
    }
    if (c >= 0x10000 && c <= 0x10FFFF) {
      c -= 0x10000;
      out[n++] = static_cast<char16_t>(0xD800 | (c >> 10));
      out[n++] = static_cast<char16_t>(0xDC00 | (c & 0x3FF));
    } else {
      out[n++] = static_cast<char16_t>(c > 0xFFFF ? 0xFFFD : c);
    }
  }
  napi_value result;
  napi_create_string_utf16(env, out.data(), n, &result);
  return result;
}

char *FromJS(napi_env env, napi_value value) {
  size_t length = 0;
  napi_get_value_string_utf16(env, value, nullptr, 0, &length);
  std::vector<char16_t> units(length + 1, 0);
  napi_get_value_string_utf16(env, value, units.data(), length + 1, &length);
  char *out = static_cast<char *>(malloc(length * 3 + 1));
  if (!out) return nullptr;
  size_t n = 0;
  for (size_t i = 0; i < length; i++) {
    uint32_t c = units[i];
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < length &&
        units[i + 1] >= 0xDC00 && units[i + 1] <= 0xDFFF) {
      c = 0x10000 + ((c - 0xD800) << 10) + (units[i + 1] - 0xDC00);
      i++;
    } else if (c >= 0xD800 && c <= 0xDFFF) {
      c = 0xFFFD;
    }
    if (c < 0x80) {
      out[n++] = static_cast<char>(c);
    } else if (c < 0x800) {
      out[n++] = static_cast<char>(0xC0 | (c >> 6));
      out[n++] = static_cast<char>(0x80 | (c & 0x3F));
    } else if (c < 0x10000) {
      out[n++] = static_cast<char>(0xE0 | (c >> 12));
      out[n++] = static_cast<char>(0x80 | ((c >> 6) & 0x3F));
      out[n++] = static_cast<char>(0x80 | (c & 0x3F));
    } else {
      out[n++] = static_cast<char>(0xF0 | (c >> 18));
      out[n++] = static_cast<char>(0x80 | ((c >> 12) & 0x3F));
      out[n++] = static_cast<char>(0x80 | ((c >> 6) & 0x3F));
      out[n++] = static_cast<char>(0x80 | (c & 0x3F));
    }
  }
  out[n] = 0;
  return out;
}

napi_value NewStringArray(napi_env env, size_t count) {
  napi_value result;
  napi_create_array_with_length(env, count, &result);
  return result;
}

// ---------------------------------------------------------------------------
// 词典资产：把 Uint8Array 的底层 ArrayBuffer 钉住，交给引擎原地读。
// ---------------------------------------------------------------------------

// release 回调：引擎销毁词典（或加载失败）时解除 napi 引用并释放 context。
struct AssetRef {
  napi_env env;
  napi_ref ref;
};

static void ReleaseAsset(void *context) {
  auto *asset = static_cast<AssetRef *>(context);
  if (asset->ref != nullptr) {
    napi_delete_reference(asset->env, asset->ref);
  }
  delete asset;
}

// 从 Uint8Array 参数取得数据指针 + 长度，并钉住底层 ArrayBuffer。
// 返回 false 表示参数不是 Uint8Array 或长度非法。
static bool PinTypedArray(napi_env env, napi_value value, const char **data, size_t *size,
                          AssetRef **asset_out) {
  bool is_typed_array = false;
  napi_is_typedarray(env, value, &is_typed_array);
  if (!is_typed_array) return false;

  napi_typedarray_type type;
  size_t length = 0;
  void *ptr = nullptr;
  napi_value arraybuffer;
  size_t byte_offset = 0;
  napi_get_typedarray_info(env, value, &type, &length, &ptr, &arraybuffer, &byte_offset);
  if (type != napi_uint8_array || ptr == nullptr || length == 0) return false;

  // 钉住底层 ArrayBuffer，防止 GC 回收它。
  napi_ref ref = nullptr;
  napi_create_reference(env, arraybuffer, 1, &ref);

  auto *asset = new AssetRef{env, ref};
  *asset_out = asset;
  *data = static_cast<const char *>(ptr);
  *size = length;
  return true;
}

napi_value LexiconCreateFromBase(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 2) {
    napi_value result; napi_get_null(env, &result); return result;
  }
  bool pinyin = false;
  napi_get_value_bool(env, args[1], &pinyin);

  const char *data = nullptr;
  size_t size = 0;
  AssetRef *asset = nullptr;
  if (!PinTypedArray(env, args[0], &data, &size, &asset)) {
    napi_value result; napi_get_null(env, &result); return result;
  }

  MPNLexicon *lexicon = mpn_lexicon_create_from_base_in_place(
      data, size, pinyin ? 1 : 0, ReleaseAsset, asset);
  if (lexicon == nullptr) {
    // 加载失败：立即释放引用。
    ReleaseAsset(asset);
  }
  napi_value result;
  napi_create_double(env, static_cast<double>(reinterpret_cast<intptr_t>(lexicon)), &result);
  return result;
}

napi_value AttachPairs(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 2) {
    napi_value result; napi_get_boolean(env, false, &result); return result;
  }
  int64_t lex = 0;
  napi_get_value_int64(env, args[0], &lex);

  const char *data = nullptr;
  size_t size = 0;
  AssetRef *asset = nullptr;
  if (!PinTypedArray(env, args[1], &data, &size, &asset)) {
    napi_value result; napi_get_boolean(env, false, &result); return result;
  }

  int attached = mpn_lexicon_attach_pairs(LEXICON(lex), data, size, ReleaseAsset, asset);
  if (!attached) {
    ReleaseAsset(asset);
  }
  napi_value result;
  napi_get_boolean(env, attached != 0, &result);
  return result;
}

napi_value LexiconDestroy(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t lex = 0;
  napi_get_value_int64(env, args[0], &lex);
  mpn_lexicon_destroy(LEXICON(lex));
  napi_value result; napi_get_undefined(env, &result); return result;
}

napi_value LexiconHeapBytes(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t lex = 0;
  napi_get_value_int64(env, args[0], &lex);
  size_t bytes = mpn_lexicon_heap_bytes(reinterpret_cast<const MPNLexicon *>(static_cast<intptr_t>(lex)));
  napi_value result;
  napi_create_double(env, static_cast<double>(bytes), &result);
  return result;
}

napi_value SessionCreate(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t lex = 0;
  napi_get_value_int64(env, args[0], &lex);
  MPNSession *session = mpn_session_create(reinterpret_cast<const MPNLexicon *>(static_cast<intptr_t>(lex)));
  napi_value result;
  napi_create_double(env, static_cast<double>(reinterpret_cast<intptr_t>(session)), &result);
  return result;
}

napi_value SessionDestroy(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t s = 0;
  napi_get_value_int64(env, args[0], &s);
  mpn_session_destroy(SESSION(s));
  napi_value result; napi_get_undefined(env, &result); return result;
}

napi_value MaxInputBytes(napi_env env, napi_callback_info info) {
  (void)info;
  napi_value result;
  napi_create_double(env, static_cast<double>(mpn_max_input_bytes()), &result);
  return result;
}

napi_value Key(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t s = 0; int32_t key = 0;
  napi_get_value_int64(env, args[0], &s);
  napi_get_value_int32(env, args[1], &key);
  napi_value result;
  napi_get_boolean(env, mpn_key(SESSION(s), key) != 0, &result);
  return result;
}

napi_value SetSimplified(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t s = 0; bool simplified = false;
  napi_get_value_int64(env, args[0], &s);
  napi_get_value_bool(env, args[1], &simplified);
  mpn_set_simplified(SESSION(s), simplified ? 1 : 0);
  napi_value result; napi_get_undefined(env, &result); return result;
}

napi_value Clear(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t s = 0;
  napi_get_value_int64(env, args[0], &s);
  mpn_clear(SESSION(s));
  napi_value result; napi_get_undefined(env, &result); return result;
}

napi_value Choose(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t s = 0; int64_t index = 0;
  napi_get_value_int64(env, args[0], &s);
  napi_get_value_int64(env, args[1], &index);
  napi_value result;
  napi_get_boolean(env, index >= 0 && mpn_choose(SESSION(s), static_cast<size_t>(index)) != 0, &result);
  return result;
}

napi_value Input(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t s = 0;
  napi_get_value_int64(env, args[0], &s);
  return ToJS(env, mpn_input(SESSION(s)));
}

napi_value Preedit(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t s = 0;
  napi_get_value_int64(env, args[0], &s);
  return ToJS(env, mpn_preedit(SESSION(s)));
}

napi_value TakeCommitted(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t s = 0;
  napi_get_value_int64(env, args[0], &s);
  napi_value result = ToJS(env, mpn_committed(SESSION(s)));
  mpn_clear_commit(SESSION(s));
  return result;
}

napi_value CandidateCount(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t s = 0;
  napi_get_value_int64(env, args[0], &s);
  size_t count = mpn_candidate_count(SESSION(s));
  napi_value result;
  napi_create_double(env, static_cast<double>(count > 0x7fffffff ? 0x7fffffff : count), &result);
  return result;
}

napi_value Candidates(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t s = 0, start = 0, count = 0;
  napi_get_value_int64(env, args[0], &s);
  napi_get_value_int64(env, args[1], &start);
  napi_get_value_int64(env, args[2], &count);
  size_t total = mpn_candidate_count(SESSION(s));
  size_t from = start < 0 ? 0 : static_cast<size_t>(start);
  size_t to = count <= 0 ? from : from + static_cast<size_t>(count);
  if (to > total) to = total;
  size_t n = to > from ? to - from : 0;
  napi_value result = NewStringArray(env, n);
  for (size_t i = 0; i < n; i++) {
    napi_set_element(env, result, i, ToJS(env, mpn_candidate(SESSION(s), from + i)));
  }
  return result;
}

// 每个候选两个数字：消耗的输入字节数、MPNCandidateKind。
napi_value CandidateDetails(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t s = 0, start = 0, count = 0;
  napi_get_value_int64(env, args[0], &s);
  napi_get_value_int64(env, args[1], &start);
  napi_get_value_int64(env, args[2], &count);
  size_t total = mpn_candidate_count(SESSION(s));
  size_t from = start < 0 ? 0 : static_cast<size_t>(start);
  size_t to = count <= 0 ? from : from + static_cast<size_t>(count);
  if (to > total) to = total;
  size_t n = to > from ? to - from : 0;
  napi_value result = NewStringArray(env, n * 2);
  for (size_t i = 0; i < n; i++) {
    MPNCandidateInfo c_info;
    memset(&c_info, 0, sizeof c_info);
    size_t index = from + i;
    int64_t consumed;
    int64_t kind;
    if (mpn_candidate_info(SESSION(s), index, &c_info, sizeof c_info)) {
      consumed = static_cast<int64_t>(c_info.consumed_bytes);
      kind = static_cast<int64_t>(c_info.kind);
    } else {
      consumed = static_cast<int64_t>(mpn_candidate_consumed(SESSION(s), index));
      kind = 0;
    }
    napi_value v_consumed, v_kind;
    napi_create_int64(env, consumed, &v_consumed);
    napi_create_int64(env, kind, &v_kind);
    napi_set_element(env, result, i * 2, v_consumed);
    napi_set_element(env, result, i * 2 + 1, v_kind);
  }
  return result;
}

// session, reading, text, weight —— 和 JNI 版 addJapaneseWord 一致。
napi_value AddJapaneseWord(napi_env env, napi_callback_info info) {
  size_t argc = 4;
  napi_value args[4];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t s = 0; int32_t weight = 0;
  napi_get_value_int64(env, args[0], &s);
  napi_get_value_int32(env, args[3], &weight);
  char *reading = FromJS(env, args[1]);
  char *text = FromJS(env, args[2]);
  int added = (reading && text) ? mpn_add_japanese_word(SESSION(s), reading, text, weight) : 0;
  free(reading);
  free(text);
  napi_value result;
  napi_get_boolean(env, added != 0, &result);
  return result;
}

napi_value MixedPinyin(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t s = 0; bool simplified = false;
  napi_get_value_int64(env, args[0], &s);
  napi_get_value_bool(env, args[2], &simplified);
  char *reading = FromJS(env, args[1]);
  const char *result = reading ? mpn_mixed_pinyin(SESSION(s), reading, simplified ? 1 : 0) : "";
  napi_value out = ToJS(env, result);
  free(reading);
  return out;
}

// {text, consumed} 的完整前导片段，或 null。
napi_value MixedPinyinPrefix(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t s = 0; bool simplified = false;
  napi_get_value_int64(env, args[0], &s);
  napi_get_value_bool(env, args[2], &simplified);
  char *reading = FromJS(env, args[1]);
  napi_value result;
  napi_get_null(env, &result);
  if (reading) {
    size_t consumed = 0;
    const char *text = mpn_mixed_pinyin_prefix(SESSION(s), reading, simplified ? 1 : 0, &consumed);
    if (text && text[0] && consumed > 0) {
      napi_create_array_with_length(env, 2, &result);
      napi_set_element(env, result, 0, ToJS(env, text));
      napi_value v_consumed;
      napi_create_double(env, static_cast<double>(consumed), &v_consumed);
      napi_set_element(env, result, 1, v_consumed);
    }
    free(reading);
  }
  return result;
}

napi_value Predict(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t s = 0, limit = 0;
  napi_get_value_int64(env, args[0], &s);
  napi_get_value_int64(env, args[2], &limit);
  char *context = FromJS(env, args[1]);
  size_t count = (context && limit > 0) ? mpn_predict(SESSION(s), context, static_cast<size_t>(limit)) : 0;
  napi_value result = NewStringArray(env, count);
  for (size_t i = 0; i < count; i++) {
    napi_set_element(env, result, i, ToJS(env, mpn_prediction(SESSION(s), i)));
  }
  free(context);
  return result;
}


// ---------------------------------------------------------------------------
// 新内核（Meowpuut-Core 0.8）：原生九键会话、原文输入、不主动词过滤。
// ---------------------------------------------------------------------------

napi_value NineKeySessionCreate(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t lex = 0;
  napi_get_value_int64(env, args[0], &lex);
  MPNSession *session =
      mpn_nine_key_session_create(reinterpret_cast<const MPNLexicon *>(static_cast<intptr_t>(lex)));
  napi_value result;
  napi_create_double(env, static_cast<double>(reinterpret_cast<intptr_t>(session)), &result);
  return result;
}

napi_value InputText(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t s = 0;
  napi_get_value_int64(env, args[0], &s);
  return ToJS(env, mpn_input_text(SESSION(s)));
}

napi_value TextNoSuggest(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t s = 0;
  napi_get_value_int64(env, args[0], &s);
  char *text = FromJS(env, args[1]);
  int flagged = (text && text[0]) ? mpn_text_no_suggest(SESSION(s), text) : 0;
  free(text);
  napi_value result;
  napi_get_boolean(env, flagged != 0, &result);
  return result;
}

// ---------------------------------------------------------------------------
// 英文引擎（mimo_en.bin，MIMO-EN-1）。englishOpen 用 copy=1：引擎自行复制
// 字节，无需钉住 ArkTS 的 ArrayBuffer（mpn_english_open 没有 release 回调，
// 与中文词典的 in-place 模式不同）。
// ---------------------------------------------------------------------------

#define ENGLISH(h) reinterpret_cast<MPNEnglish *>(static_cast<intptr_t>(h))

napi_value EnglishOpen(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  napi_value result;
  napi_get_null(env, &result);
  bool is_typed_array = false;
  if (argc < 1) return result;
  napi_is_typedarray(env, args[0], &is_typed_array);
  if (!is_typed_array) return result;
  napi_typedarray_type type;
  size_t length = 0;
  void *ptr = nullptr;
  napi_value arraybuffer;
  size_t byte_offset = 0;
  napi_get_typedarray_info(env, args[0], &type, &length, &ptr, &arraybuffer, &byte_offset);
  if (type != napi_uint8_array || ptr == nullptr || length == 0) return result;
  MPNEnglish *english = mpn_english_open(ptr, length, 1);
  napi_create_double(env, static_cast<double>(reinterpret_cast<intptr_t>(english)), &result);
  return result;
}

napi_value EnglishClose(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t h = 0;
  napi_get_value_int64(env, args[0], &h);
  mpn_english_close(ENGLISH(h));
  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

napi_value EnglishWordCount(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t h = 0;
  napi_get_value_int64(env, args[0], &h);
  napi_value result;
  napi_create_double(env, static_cast<double>(mpn_english_word_count(ENGLISH(h))), &result);
  return result;
}

// 可空字符串参数：null/undefined 传 nullptr，否则 UTF-8。
static char *OptionalString(napi_env env, napi_value value) {
  napi_valuetype type;
  napi_typeof(env, value, &type);
  if (type == napi_null || type == napi_undefined) return nullptr;
  return FromJS(env, value);
}

// 一次查询返回一个数组：[text0, kind0, text1, kind1, ...]（每个英文操作最多 8 个结果）。
static napi_value EnglishQueryRun(napi_env env, MPNEnglishQuery *query, size_t count) {
  napi_value result = NewStringArray(env, count * 2);
  for (size_t i = 0; i < count; i++) {
    napi_set_element(env, result, i * 2, ToJS(env, mpn_english_text(query, i)));
    napi_value kind;
    napi_create_int64(env, mpn_english_kind(query, i), &kind);
    napi_set_element(env, result, i * 2 + 1, kind);
  }
  return result;
}

napi_value EnglishComplete(napi_env env, napi_callback_info info) {
  size_t argc = 4;
  napi_value args[4];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t h = 0;
  napi_get_value_int64(env, args[0], &h);
  uint32_t flags = 0;
  napi_get_value_uint32(env, args[3], &flags);
  char *prefix = FromJS(env, args[1]);
  char *before = OptionalString(env, args[2]);
  MPNEnglishQuery *query = mpn_english_query_create();
  size_t count = prefix ? mpn_english_complete(query, ENGLISH(h), prefix, before, flags) : 0;
  napi_value result = EnglishQueryRun(env, query, count);
  mpn_english_query_destroy(query);
  free(prefix);
  free(before);
  return result;
}

napi_value EnglishCorrect(napi_env env, napi_callback_info info) {
  size_t argc = 4;
  napi_value args[4];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t h = 0;
  napi_get_value_int64(env, args[0], &h);
  uint32_t flags = 0;
  napi_get_value_uint32(env, args[3], &flags);
  char *word = FromJS(env, args[1]);
  char *before = OptionalString(env, args[2]);
  MPNEnglishQuery *query = mpn_english_query_create();
  size_t count = word ? mpn_english_correct(query, ENGLISH(h), word, before, flags) : 0;
  napi_value result = EnglishQueryRun(env, query, count);
  mpn_english_query_destroy(query);
  free(word);
  free(before);
  return result;
}

napi_value EnglishPredict(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t h = 0;
  napi_get_value_int64(env, args[0], &h);
  uint32_t flags = 0;
  napi_get_value_uint32(env, args[2], &flags);
  char *before = OptionalString(env, args[1]);
  MPNEnglishQuery *query = mpn_english_query_create();
  size_t count = before ? mpn_english_predict(query, ENGLISH(h), before, flags) : 0;
  napi_value result = EnglishQueryRun(env, query, count);
  mpn_english_query_destroy(query);
  free(before);
  return result;
}

napi_value EnglishNineKey(napi_env env, napi_callback_info info) {
  size_t argc = 4;
  napi_value args[4];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t h = 0;
  napi_get_value_int64(env, args[0], &h);
  uint32_t flags = 0;
  napi_get_value_uint32(env, args[3], &flags);
  char *digits = FromJS(env, args[1]);
  char *before = OptionalString(env, args[2]);
  MPNEnglishQuery *query = mpn_english_query_create();
  size_t count = digits ? mpn_english_nine_key(query, ENGLISH(h), digits, before, flags) : 0;
  napi_value result = EnglishQueryRun(env, query, count);
  mpn_english_query_destroy(query);
  free(digits);
  free(before);
  return result;
}

napi_value EnglishIsBlocked(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int64_t h = 0;
  napi_get_value_int64(env, args[0], &h);
  char *word = FromJS(env, args[1]);
  int blocked = word ? mpn_english_is_blocked(ENGLISH(h), word) : 0;
  free(word);
  napi_value result;
  napi_get_boolean(env, blocked != 0, &result);
  return result;
}

// 给中文（拼音/九键）词库挂上英文词（新内核：拼音与九键打字出英文词，
// 排在中文之后，屏蔽词永不主动出）。
napi_value AttachEnglish(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  napi_value result;
  napi_get_boolean(env, false, &result);
  if (argc < 2) return result;
  int64_t lex = 0;
  napi_get_value_int64(env, args[0], &lex);

  const char *data = nullptr;
  size_t size = 0;
  AssetRef *asset = nullptr;
  if (!PinTypedArray(env, args[1], &data, &size, &asset)) return result;

  int attached = mpn_lexicon_attach_english(LEXICON(lex), data, size, ReleaseAsset, asset);
  if (!attached) {
    ReleaseAsset(asset);
  }
  napi_get_boolean(env, attached != 0, &result);
  return result;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"lexiconCreateFromBase", nullptr, LexiconCreateFromBase, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"attachPairs", nullptr, AttachPairs, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"lexiconDestroy", nullptr, LexiconDestroy, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"lexiconHeapBytes", nullptr, LexiconHeapBytes, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"sessionCreate", nullptr, SessionCreate, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"sessionDestroy", nullptr, SessionDestroy, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"maxInputBytes", nullptr, MaxInputBytes, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"key", nullptr, Key, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"setSimplified", nullptr, SetSimplified, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"clear", nullptr, Clear, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"choose", nullptr, Choose, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"input", nullptr, Input, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"preedit", nullptr, Preedit, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"takeCommitted", nullptr, TakeCommitted, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"candidateCount", nullptr, CandidateCount, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"candidates", nullptr, Candidates, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"candidateDetails", nullptr, CandidateDetails, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"addJapaneseWord", nullptr, AddJapaneseWord, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"mixedPinyin", nullptr, MixedPinyin, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"mixedPinyinPrefix", nullptr, MixedPinyinPrefix, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"predict", nullptr, Predict, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"nineKeySessionCreate", nullptr, NineKeySessionCreate, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"inputText", nullptr, InputText, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"textNoSuggest", nullptr, TextNoSuggest, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"attachEnglish", nullptr, AttachEnglish, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"englishOpen", nullptr, EnglishOpen, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"englishClose", nullptr, EnglishClose, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"englishWordCount", nullptr, EnglishWordCount, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"englishComplete", nullptr, EnglishComplete, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"englishCorrect", nullptr, EnglishCorrect, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"englishPredict", nullptr, EnglishPredict, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"englishNineKey", nullptr, EnglishNineKey, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"englishIsBlocked", nullptr, EnglishIsBlocked, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  return exports;
}

} // namespace

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "meowpuut",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterMeowpuutModule(void) {
  napi_module_register(&demoModule);
}