#![forbid(unsafe_code)]
//! Nine-key (T9) pinyin expansion and prefix candidate collection.
//!
//! Nine-key pinyin feeds digits `2..=9`; each digit expands to three or four
//! Latin letters (`2=abc`, …, `7=pqrs`, `8=tuv`, `9=wxyz`). The lexicon indexes
//! word buckets by their *untoned* reading (`bare`), so `Lexicon::range(prefix)`
//! already answers the "toneless prefix" query natively — this module only has
//! to enumerate the digit→letter expansions and merge the bucket hits.
//!
//! # Examples
//!
//! ```
//! use meowpuut_core::nine_key::{expand_nine_key, nine_key_candidates, NineKeyHit};
//! use std::sync::Arc;
//! use meowpuut_core::Lexicon;
//!
//! // "64" expands to 3 x 3 = 9 toneless prefixes (g/h/i x m/n/o).
//! let expansions = expand_nine_key("64");
//! assert_eq!(expansions.len(), 9);
//! assert!(expansions.contains(&"ni".to_string()));
//!
//! let tsv = concat!(
//!     "MEOWPUUT-PINYIN-1\n",
//!     "hao\thao3\t好\t好\t4700\n",
//!     "ni\tni3\t你\t你\t4800\n",
//!     "nihao\tni3hao3\t你好\t你好\t5400\n",
//!     "# context\n",
//!     "你好\t600\n",
//! );
//! let lex = Arc::new(Lexicon::load(tsv).unwrap());
//! let mut out: Vec<NineKeyHit> = Vec::new();
//! let n = nine_key_candidates(&lex, "64", true, &mut out);
//! // Prefixes "ni" and "mi"/"oi"/… expand; only "ni…" buckets carry words.
//! assert!(n >= 2, "ni and nihao both start with ni");
//! assert!(out.iter().any(|h| h.text == "你好"));
//! ```

use std::collections::HashSet;

use crate::lexicon::Lexicon;

/// ASCII digits `2..=9` mapped to their T9 Latin letters (industry standard).
pub const NINE_KEY_LETTERS: [(u8, &[u8]); 8] = [
    (b'2', b"abc"),
    (b'3', b"def"),
    (b'4', b"ghi"),
    (b'5', b"jkl"),
    (b'6', b"mno"),
    (b'7', b"pqrs"),
    (b'8', b"tuv"),
    (b'9', b"wxyz"),
];

/// Letters for one ASCII digit `2..=9`, or `None` for any other byte.
#[inline]
pub fn nine_key_letters(digit: u8) -> Option<&'static [u8]> {
    NINE_KEY_LETTERS
        .iter()
        .find(|(d, _)| *d == digit)
        .map(|(_, letters)| *letters)
}

/// Expands a digit sequence into every Cartesian product of toneless prefixes.
///
/// Digits `2..=9` expand; any other byte is skipped. The result holds exactly
/// the full-length expansions, ordered so that all prefixes of a given length
/// are contiguous, which lets a caller prune a branch as soon as
/// `range(prefix)` is empty.
pub fn expand_nine_key(digits: &str) -> Vec<String> {
    let mut out: Vec<String> = vec![String::new()];
    for digit in digits.bytes() {
        let letters = match nine_key_letters(digit) {
            Some(l) => l,
            None => continue,
        };
        let prev_len = out.len();
        let mut next: Vec<String> = Vec::with_capacity(prev_len * letters.len());
        for i in 0..prev_len {
            let base = &out[i];
            for &letter in letters {
                let mut s = base.clone();
                s.push(letter as char);
                next.push(s);
            }
        }
        out = next;
    }
    out
}

/// One collected nine-key candidate.
#[derive(Debug, Clone, PartialEq)]
pub struct NineKeyHit {
    pub text: String,
    pub weight: i32,
}

/// Collects lexicon words whose untoned reading starts with any digit-expanded
/// prefix, deduplicated by word text, heaviest first.
///
/// A single expansion prefix is a *prefix*, not an exact bucket: `"64"` expands
/// to `"ni"`, whose matches are `ni`, `nihao`, `nide`, … So this walks the
/// sorted bucket table from `lower_bound_bucket(prefix)` while the bucket key
/// still starts with `prefix`, unioning every bucket's word range.
///
/// This is the "continuous, no syllable-boundary" engine: it expands the whole
/// digit string as one run. Syllable segmentation (e.g. `64426` = `ni`+`hao`)
/// needs the Android reference output to calibrate and is intentionally left
/// out of this first slice.
pub fn nine_key_candidates(lexicon: &Lexicon, digits: &str, hans: bool, out: &mut Vec<NineKeyHit>) -> usize {
    out.clear();
    let expansions = expand_nine_key(digits);
    let mut seen: HashSet<String> = HashSet::new();
    for prefix in &expansions {
        // Walk buckets from the lower bound while the key keeps the prefix.
        let mut bucket_idx = lexicon.lower_bound_bucket(prefix);
        let bucket_count = lexicon.buckets.len();
        while bucket_idx < bucket_count {
            let key = lexicon.buckets.key(&lexicon.storage, bucket_idx);
            if !key.starts_with(prefix.as_str()) {
                break;
            }
            let (lo, hi) = lexicon.buckets.range(bucket_idx);
            for idx in lo..hi {
                let text = lexicon.words.text(&lexicon.storage, idx, hans);
                if text.is_empty() || !seen.insert(text.to_string()) {
                    continue;
                }
                out.push(NineKeyHit {
                    text: text.to_string(),
                    weight: lexicon.words.weight(idx),
                });
            }
            bucket_idx += 1;
        }
    }
    out.sort_by(|a, b| b.weight.cmp(&a.weight));
    out.len()
}