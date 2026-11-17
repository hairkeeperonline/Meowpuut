/**
 * Round 65 ① 仿真：玻璃静态层离屏缓存（缓存键 / 失效 / 位图生命周期 / 计数器）。
 * 把 MeowpuutKeyboard.drawCandidateBar 的缓存段与 renderGlassCache 的守卫逐行移植到 Node，
 * 用「假 OffscreenCanvas / 假 ImageBitmap」记录调用，验证 9 类场景。
 * 运行：node tools/sim-glass-cache.mjs （全部通过退出码 0）
 */

const Shape = { CAPSULE: 'CAPSULE', ROUNDED: 'ROUNDED' };

/** 假的 Look：引用身份即语义（与 ArkTS 一致）。 */
class Look {
  constructor(dark, shape, palette, strength, cats, effects) {
    this.dark = dark; this.shape = shape; this.palette = palette;
    this.strength = strength; this.cats = cats; this.effects = effects;
  }
}

/** 假 ImageBitmap：记录是否已释放；释放后再被绘制视为错误。 */
class FakeBitmap {
  static _seq = 0;
  constructor(w, h) {
    this.id = ++FakeBitmap._seq;
    this.width = w; this.height = h;
    this.closed = false;
    FakeBitmap.all.push(this);
  }
  close() {
    if (this.closed) throw new Error(`bitmap #${this.id} closed twice`);
    this.closed = true;
    FakeBitmap.closedCount++;
  }
}
FakeBitmap.all = [];
FakeBitmap.closedCount = 0;
FakeBitmap.reset = () => { FakeBitmap.all = []; FakeBitmap.closedCount = 0; FakeBitmap._seq = 0; };

/** 假画布：记录 drawImage 调用，若画到已关闭的位图则抛错。 */
class FakeCtx {
  constructor() { this.drawn = []; this.cleared = 0; }
  clearRect() { this.cleared++; this.drawn = []; }
  save() {}
  restore() {}
  drawImage(bmp) {
    if (bmp.closed) throw new Error(`drew CLOSED bitmap #${bmp.id}`);
    this.drawn.push(bmp.id);
  }
}

/** 被测对象的缓存相关裁剪版（逻辑与 MeowpuutKeyboard 一致）。 */
class BarCache {
  constructor() {
    this.glassCacheBitmap = null;
    this.glassCacheKey = '';
    this.glassCacheLook = null;
    this.glassHitFrames = 0;
    this.glassDirectFrames = 0;
    this.renderCount = 0;
    this.renderFails = false;
    this.pxRatio = 3;
  }

  /** 与 renderGlassCache 等价：渲染失败返回 null（不抛）。 */
  renderGlassCache(vpW, vpH) {
    if (vpW <= 1 || vpH <= 1) return null;       // 守卫
    if (this.renderFails) return null;
    this.renderCount++;
    const k = this.pxRatio;
    return new FakeBitmap(Math.round(vpW * k), Math.round(vpH * k));
  }

  /**
   * 与 drawCandidateBar 的缓存段 + 回贴段等价。
   * env = { w, h, idiom, showCats, festivalId, festivalLoadedId, festArtReady, look }
   */
  frame(ctx, env) {
    const w = env.w, h = env.h;
    ctx.clearRect(0, 0, w, h);
    const cacheKey = `${w}x${h}|${env.idiom}|${env.showCats ? 1 : 0}|` +
      `${env.festivalId}|${env.festivalLoadedId}|${env.festArtReady}`;
    let bmp = this.glassCacheBitmap;
    if (bmp === null || cacheKey !== this.glassCacheKey || this.glassCacheLook !== env.look) {
      const fresh = this.renderGlassCache(w, h);
      if (fresh !== null) {
        const old = this.glassCacheBitmap;
        this.glassCacheBitmap = fresh;
        this.glassCacheKey = cacheKey;
        this.glassCacheLook = env.look;
        if (old !== null && old !== fresh) {
          try { old.close(); } catch (e) { /* 已释放则忽略 */ }
        }
        bmp = fresh;
      }
    }
    if (bmp !== null) {
      ctx.drawImage(bmp);
      this.glassHitFrames++;
    } else {
      this.glassDirectFrames++;   // 回退直绘
    }
    return bmp;
  }

  invalidate() { this.glassCacheKey = ''; }  // rebuild() 里的失效
}

let fail = 0, pass = 0;
const eq = (name, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (ok) { pass++; console.log(`  ✓ ${name}`); }
  else { fail++; console.log(`  ✗ ${name} — got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); }
};

const baseEnv = () => ({
  w: 360, h: 56, idiom: 'PHONE_PORTRAIT', showCats: true,
  festivalId: '-', festivalLoadedId: '-', festArtReady: '0',
  look: new Look(false, Shape.CAPSULE, 'ROSE', 'BALANCED', true, true),
});

console.log('=== 1. 同参数连续 10 帧：只渲染 1 次，命中 10 次 ===');
{
  FakeBitmap.reset();
  const c = new BarCache(), ctx = new FakeCtx(), env = baseEnv();
  for (let i = 0; i < 10; i++) c.frame(ctx, env);
  eq('renderCount', c.renderCount, 1);
  eq('glassHitFrames', c.glassHitFrames, 10);
  eq('glassDirectFrames', c.glassDirectFrames, 0);
  eq('未产生多余位图', FakeBitmap.all.length, 1);
  eq('缓存位图未在命中路径被释放', c.glassCacheBitmap.closed, false);
}

console.log('\n=== 2. 每次都是新 Look 实例（模拟「每帧 new Look」的退化场景）===');
{
  FakeBitmap.reset();
  const c = new BarCache(), ctx = new FakeCtx();
  for (let i = 0; i < 5; i++) {
    const env = baseEnv();
    env.look = new Look(false, Shape.CAPSULE, 'ROSE', 'BALANCED', true, true); // 引用每次都变
    c.frame(ctx, env);
  }
  eq('每次都重渲染（说明引用失效确实生效）', c.renderCount, 5);
  // 注意计数器语义（与真实代码一致）：glassHitFrames 计的是「位图回贴成功」的帧，
  // glassDirectFrames 计的是「回退直绘」的帧。退化场景里每帧都重渲染、但渲染成功后
  // 仍然回贴，所以 hit=5 是**正确**的；真正暴露退化的是 renderCount 与 direct=0。
  eq('回贴帧数 = 5（每帧都重渲染后回贴）', c.glassHitFrames, 5);
  eq('直绘回退帧数 = 0（离屏路径本身没坏）', c.glassDirectFrames, 0);
  eq('旧位图全部被释放，只保留最后一张', FakeBitmap.closedCount, 4);
}

console.log('\n=== 3. 位图释放正确性：换键后旧位图必须 close，且绝不再被绘制 ===');
{
  FakeBitmap.reset();
  const c = new BarCache(), ctx = new FakeCtx();
  const e1 = baseEnv();
  c.frame(ctx, e1);
  const first = c.glassCacheBitmap;
  const e2 = baseEnv(); e2.w = 400; e2.look = e1.look;   // 只有宽度变
  c.frame(ctx, e2);
  eq('旧位图已释放', first.closed, true);
  eq('新位图未释放', c.glassCacheBitmap.closed, false);
  eq('当前位图是新的一张', c.glassCacheBitmap !== first, true);
  // 再画 3 帧，不能触发「画已关闭位图」
  let threw = null;
  try { for (let i = 0; i < 3; i++) c.frame(ctx, e2); } catch (err) { threw = err.message; }
  eq('后续帧未触碰已释放位图', threw, null);
  eq('renderCount（360→400 各一次）', c.renderCount, 2);
}

console.log('\n=== 4. 缓存键各分量逐一失效 ===');
{
  const mutators = {
    '宽度 w': (e) => { e.w = 401; },
    '高度 h': (e) => { e.h = 57; },
    'idiom': (e) => { e.idiom = 'TABLET'; },
    '猫开关': (e) => { e.showCats = false; },
    '节日 id': (e) => { e.festivalId = 'newyear'; },
    '节日贴图加载态': (e) => { e.festivalLoadedId = 'newyear'; },
    '节日贴图就绪': (e) => { e.festArtReady = '1'; },
  };
  for (const [name, mutate] of Object.entries(mutators)) {
    FakeBitmap.reset();
    const c = new BarCache(), ctx = new FakeCtx();
    const e = baseEnv();
    c.frame(ctx, e);
    c.frame(ctx, e);
    const before = c.renderCount;
    mutate(e);
    c.frame(ctx, e);
    eq(`${name} 变化 → 重新渲染`, c.renderCount, before + 1);
  }
  // 无变化时不应多渲染
  FakeBitmap.reset();
  const c = new BarCache(), ctx = new FakeCtx(), e = baseEnv();
  c.frame(ctx, e); c.frame(ctx, e); c.frame(ctx, e);
  eq('纯重复帧不重渲染', c.renderCount, 1);
}

console.log('\n=== 5. Look 引用变化 → 失效；内容相同但新实例也必须失效 ===');
{
  FakeBitmap.reset();
  const c = new BarCache(), ctx = new FakeCtx();
  const e = baseEnv();
  c.frame(ctx, e); c.frame(ctx, e);
  // 同内容、新实例（applyLook 重建）
  e.look = new Look(false, Shape.CAPSULE, 'ROSE', 'BALANCED', true, true);
  c.frame(ctx, e);
  eq('同内容新实例仍重渲染（引用比较，安全侧）', c.renderCount, 2);
  // 换深色
  e.look = new Look(true, Shape.CAPSULE, 'ROSE', 'BALANCED', true, true);
  c.frame(ctx, e);
  eq('深色切换重渲染', c.renderCount, 3);
}

console.log('\n=== 6. rebuild() 的失效：清 key 但保留位图（应重渲染一次，旧图释放）===');
{
  FakeBitmap.reset();
  const c = new BarCache(), ctx = new FakeCtx(), e = baseEnv();
  c.frame(ctx, e); c.frame(ctx, e);
  const beforeBmp = c.glassCacheBitmap;
  c.invalidate();                 // rebuild() 里 glassCacheKey = ''
  c.frame(ctx, e);
  eq('invalidate 后重渲染一次', c.renderCount, 2);
  eq('旧位图被释放', beforeBmp.closed, true);
  eq('新位图可用', c.glassCacheBitmap.closed, false);
}

console.log('\n=== 7. 早期 kbWidth=0 / 高度过小：不污染缓存键，不留坏位图 ===');
{
  FakeBitmap.reset();
  const c = new BarCache(), ctx = new FakeCtx();
  const e0 = baseEnv(); e0.w = 0; e0.h = 0;
  c.frame(ctx, e0);
  eq('尺寸过小时不渲染', c.renderCount, 0);
  eq('缓存键仍为空（不被 0x0 污染）', c.glassCacheKey, '');
  eq('无位图', c.glassCacheBitmap, null);
  eq('走直绘回退', c.glassDirectFrames, 1);
  // 尺寸就绪
  const e1 = baseEnv();
  c.frame(ctx, e1);
  eq('尺寸就绪后正常渲染', c.renderCount, 1);
  eq('走命中', c.glassHitFrames, 1);
}

console.log('\n=== 8. 渲染失败：不写入缓存键，持续回退直绘，恢复后能自愈 ===');
{
  FakeBitmap.reset();
  const c = new BarCache(), ctx = new FakeCtx(), e = baseEnv();
  c.renderFails = true;
  c.frame(ctx, e); c.frame(ctx, e);
  eq('失败时缓存键仍为空', c.glassCacheKey, '');
  eq('失败时无位图', c.glassCacheBitmap, null);
  eq('失败走直绘 2 次', c.glassDirectFrames, 2);
  eq('失败不计入命中', c.glassHitFrames, 0);
  c.renderFails = false;
  c.frame(ctx, e);
  eq('恢复后成功渲染', c.renderCount, 1);
  eq('恢复后走命中', c.glassHitFrames, 1);
}

console.log('\n=== 9. 长跑稳定性：200 帧含 4 次主题切换，位图数量与释放数守恒 ===');
{
  FakeBitmap.reset();
  const c = new BarCache(), ctx = new FakeCtx();
  const e = baseEnv();
  let switches = 0;
  for (let i = 0; i < 200; i++) {
    // i=40,80,120,160 各切一次主题（i>0 && i%40===0）
    if (i > 0 && i % 40 === 0) {
      e.look = new Look(i % 80 === 0, Shape.CAPSULE, 'ROSE', 'BALANCED', true, true);
      switches++;
    }
    c.frame(ctx, e);
  }
  eq('实际主题切换次数', switches, 4);
  eq('渲染次数 = 首次 + 4 次切换', c.renderCount, 5);
  eq('回贴帧数 = 200（每次渲染成功后都回贴）', c.glassHitFrames, 200);
  eq('直绘回退 0 次', c.glassDirectFrames, 0);
  eq('创建位图 5 张', FakeBitmap.all.length, 5);
  eq('释放位图 4 张（保留当前 1 张）', FakeBitmap.closedCount, 4);
  eq('当前位图未释放', c.glassCacheBitmap.closed, false);
  eq('位图守恒：创建 = 释放 + 1', FakeBitmap.all.length, FakeBitmap.closedCount + 1);
}

console.log(`\n=== 结果：${fail === 0 ? '全部通过' : fail + ' 项失败'}（通过 ${pass}）===`);
process.exit(fail === 0 ? 0 : 1);
