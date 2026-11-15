/**
 * 猫的贴图数据（由 scripts/render_cats.py 从 assets/brand/cats/cats.json 生成）。
 * 与 Android ime/CatSpriteData.kt、iOS CatSprites.swift 完全一致。
 */

export class PawPoint {
  x: number;
  halfWidth: number;
  depth: number;
  constructor(x: number, halfWidth: number, depth: number) {
    this.x = x;
    this.halfWidth = halfWidth;
    this.depth = depth;
  }
}

export class CatSprite {
  name: string;
  width: number;
  height: number;
  anchorX: number;
  anchorY: number;
  left: number;
  top: number;
  right: number;
  bottom: number;
  cutLeft: number;
  cutRight: number;
  paws: PawPoint[];

  constructor(name: string, width: number, height: number, anchorX: number, anchorY: number,
    left: number, top: number, right: number, bottom: number, cutLeft: number, cutRight: number,
    paws: PawPoint[]) {
    this.name = name;
    this.width = width;
    this.height = height;
    this.anchorX = anchorX;
    this.anchorY = anchorY;
    this.left = left;
    this.top = top;
    this.right = right;
    this.bottom = bottom;
    this.cutLeft = cutLeft;
    this.cutRight = cutRight;
    this.paws = paws;
  }
}

export const CatSpriteData: Map<string, CatSprite> = new Map<string, CatSprite>([
  ['mimimo_edge_rest', new CatSprite('mimimo_edge_rest', 72, 80, 0.5, 0.84,
    0.1019, 0.0875, 0.8935, 0.8833, 0.1574, 0.8194,
    [new PawPoint(0.4537, 0.0926, 0.0375), new PawPoint(0.7106, 0.0903, 0.0375)])],
  ['mimimo_edge_peek', new CatSprite('mimimo_edge_peek', 64, 64, 0.5, 0.84,
    0.0833, 0.0885, 0.9167, 0.8906, 0.1979, 0.8229,
    [new PawPoint(0.3125, 0.1094, 0.0469), new PawPoint(0.7109, 0.1068, 0.0469)])],
  ['mimimo_edge_lounge', new CatSprite('mimimo_edge_lounge', 112, 72, 0.5, 0.84,
    0.0595, 0.088, 0.9435, 0.9352, 0.1161, 0.881,
    [new PawPoint(0.2173, 0.0625, 0.0093), new PawPoint(0.4286, 0.0595, 0.0972)])],
  ['mimimo_side_hold', new CatSprite('mimimo_side_hold', 64, 88, 0.8516, 0.583,
    0.0833, 0.053, 0.9167, 0.9053, 0, 0, [])],
  ['momo_edge_rest', new CatSprite('momo_edge_rest', 72, 80, 0.5, 0.84,
    0.1204, 0.0833, 0.8796, 0.8833, 0.1898, 0.8194,
    [new PawPoint(0.4699, 0.0903, 0.0417), new PawPoint(0.7153, 0.0903, 0.0417)])],
  ['momo_edge_peek', new CatSprite('momo_edge_peek', 64, 64, 0.5, 0.84,
    0.0938, 0.0885, 0.9062, 0.901, 0.2031, 0.8177,
    [new PawPoint(0.3151, 0.112, 0.0573), new PawPoint(0.7083, 0.1094, 0.0573)])],
  ['momo_edge_lounge', new CatSprite('momo_edge_lounge', 112, 72, 0.5, 0.84,
    0.0536, 0.0972, 0.9435, 0.9491, 0.1042, 0.8839,
    [new PawPoint(0.6042, 0.0655, 0.1111), new PawPoint(0.817, 0.0551, 0.0139)])],
  ['momo_side_hold', new CatSprite('momo_side_hold', 64, 88, 0.1263, 0.5666,
    0.0938, 0.053, 0.9062, 0.9053, 0, 0, [])],
]);
