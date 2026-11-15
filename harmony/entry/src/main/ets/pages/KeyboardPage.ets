/**
 * 软键盘面板页面（setUiContent 的目标）。渲染 MeowpuutKeyboard，
 * 触控动作经 KeyboardHost 回调回输入法服务。
 */
import { MeowpuutKeyboard } from '../ui/MeowpuutKeyboard';
import { KeyboardHost } from '../ui/KeyboardHost';
import { Key } from '../ui/Keys';

@Entry
@Component
struct KeyboardPage {
  private host: KeyboardHost = KeyboardHost.get();
  /** 悬浮键盘拖动把手：悬浮态顶部 32px 高的拖动条（PanGesture → panel.moveTo）。 */
  private dragAccumX: number = 0;
  private dragAccumY: number = 0;
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
              this.dragAccumX = 0;
              this.dragAccumY = 0;
            })
            .onActionUpdate((event: GestureEvent) => {
              // 累计偏移（event 提供的是增量），过 24px 批量提交一次 moveTo。
              this.dragAccumX += event.offsetX;
              this.dragAccumY += event.offsetY;
              if (Math.abs(this.dragAccumX) >= 24 || Math.abs(this.dragAccumY) >= 24) {
                this.host.callbacks?.onDragPanel(Math.round(this.dragAccumX), Math.round(this.dragAccumY));
                this.dragAccumX = 0;
                this.dragAccumY = 0;
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
        onPunctuationEvt: (mark: string) => this.host.callbacks?.onPunctuation(mark),
        onToggleExpandedEvt: () => this.host.callbacks?.onToggleExpanded(),
        onPetEvt: (cat: string) => this.host.callbacks?.onPet(cat),
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}