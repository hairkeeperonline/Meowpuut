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
              // offsetX/Y 是相对手势起点的总位移：把总位移作为一次增量提交
              // （减去上一次已提交的基线），每帧都 moveTo —— 不做 24px 批量，
              // 批量化会让面板一跳一跳不跟手（用户反馈「拖动不丝滑」）。
              const dx = event.offsetX - this.dragBaseX;
              const dy = event.offsetY - this.dragBaseY;
              if (dx !== 0 || dy !== 0) {
                this.dragBaseX = event.offsetX;
                this.dragBaseY = event.offsetY;
                this.host.callbacks?.onDragPanel(Math.round(dx), Math.round(dy));
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
        onHideEvt: () => this.host.callbacks?.onHide(),
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}