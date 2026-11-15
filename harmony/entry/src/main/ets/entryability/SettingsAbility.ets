/**
 * 设置界面（对应 Android 的 SettingsActivity）。
 *
 * 鸿蒙侧必须有一个普通 UIAbility 作为应用主入口（mainElement 只能指向
 * UIAbility，不能指向 inputMethod 类型的 ExtensionAbility）。否则从桌面
 * 图标启动时系统找不到可展示的页面，会被重定向到系统权限管理页。
 */
import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const TAG = 'Meowpuut-Settings';

export default class SettingsAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/SettingsPage', (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
      }
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(0x0000, TAG, 'onConfigurationUpdate');
  }
}
