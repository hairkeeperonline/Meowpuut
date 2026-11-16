/**
 * 软键盘面板页面（setUiContent 的目标）。渲染 MeowpuutKeyboard，
 * 触控动作经 KeyboardHost 回调回输入法服务。
 */
import { MeowpuutKeyboard } from '../ui/MeowpuutKeyboard';
import { KeyboardHost } from '../ui/KeyboardHost';
import { Key } from '../ui/Keys';
import { display } from '@kit.ArkUI';

@Entry
@Component
struct KeyboardPage {
  private host: KeyboardHost = KeyboardHost.get();
  /** 拖动起点（手势开始时的累计偏移为 0，offsetX/Y 即相对起点的总位移）。 */
  private dragBaseX: number = 0;
  private dragBaseY: number = 0;
  /** 悬浮态开关：ability 通过 AppStorage 写入（普通类字段非响应式，必须走 AppStorage）。 */
  @StorageLink('meowpuutDraggable') floatDraggable: boolean = false;

  build() {
    Column() {
      // 悬浮拖动条（贴底态隐藏；悬浮态由 AppStorage 联动显示）。
      if (this.floatDraggable) {
        Row() {
          Column()
            .width(48)
            .height(5)
            .borderRadius(3)
            .backgroundColor('#8C787880')
        }
        .width('100%')
        .height(32)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .gesture(
          PanGesture({ fingers: 1, distance: 2 })
            .onActionStart(() => {
              this.dragBaseX = 0;
              this.dragBaseY = 0;
            })
            .onActionUpdate((event: GestureEvent) => {
              // offsetX/Y 是相对手势起点的总位移（vp）：取与上次提交基线的差作为
              // 本帧增量，乘 density 换算成 px 再提交 —— panel.moveTo 单位是 px，
              // 不换算的话面板只跟 1/3 速度（真机反馈 round 60-3「很慢不跟手」）。
              const dx = event.offsetX - this.dragBaseX;
              const dy = event.offsetY - this.dragBaseY;
              if (dx !== 0 || dy !== 0) {
                this.dragBaseX = event.offsetX;
                this.dragBaseY = event.offsetY;
                const density = display.getDefaultDisplaySync().densityDPI / 160;
                this.host.callbacks?.onDragPanel(Math.round(dx * density), Math.round(dy * density));
              }
            })
        )
      }
      MeowpuutKeyboard({
        onKeyDownEvt: (key: Key) => this.host.callbacks?.onKeyDown(key),
        onKeyEvt: (key: Key, text: string | null) => this.host.callbacks?.onKey(key, text),
        onDeleteEvt: (word: boolean) => this.host.callbacks?.onDelete(word),
        onShiftDownEvt: () => this.host.callbacks?.onShiftDown(),
        onShiftUpEvt: (typed: boolean) => this.host.callbacks?.onShiftUp(typed),
        onPageEvt: (page: number) => this.host.callbacks?.onPage(page),
        onCursorStartEvt: () => this.host.callbacks?.onCursorStart(),
        onCursorMoveEvt: (steps: number) => this.host.callbacks?.onCursorMove(steps),
        onCursorEndEvt: () => this.host.callbacks?.onCursorEnd(),
        onTickEvt: () => this.host.callbacks?.onTick(),
        onCandidateEvt: (index: number) => this.host.callbacks?.onCandidate(index),
        onPredictionEvt: (text: string) => this.host.callbacks?.onPrediction(text),
        onPasteEvt: () => this.host.callbacks?.onPaste(),
        onPunctuationEvt: (mark: string) => this.host.callbacks?.onPunctuation(mark),
        onToggleExpandedEvt: () => this.host.callbacks?.onToggleExpanded(),
        onPetEvt: (cat: string) => this.host.callbacks?.onPet(cat),
        onHideEvt: () => this.host.callbacks?.onHide(),
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}