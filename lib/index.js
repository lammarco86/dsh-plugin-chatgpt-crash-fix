/**
 * dsh-plugin-chatgpt-crash-fix — Cordis plugin entry.
 *
 * Registers a `/chatgpt-crash-fix` command that surfaces the bundled
 * diagnostic playbook and the location of the runnable PowerShell scripts.
 * The actual diagnosis/fix is executed by the agent following skills/
 * chatgpt-crash-fix/SKILL.md and calling the bundled scripts with its own
 * shell tool — this package is the knowledge + tooling carrier, not a
 * privileged executor.
 *
 * All capabilities are optional and guarded with `ctx.get()`; the plugin
 * degrades gracefully on hosts without the `commands` seam.
 */

/** Where this package's assets live at runtime. */
function assetsRoot() {
  return new URL('..', import.meta.url)
}

export default {
  apply(ctx) {
    const commands = ctx.get('commands')
    if (commands !== undefined) {
      commands.register({
        name: 'chatgpt-crash-fix',
        description: 'ChatGPT/Codex desktop crash: print the diagnosis & fix playbook and locate bundled scripts.',
        recordInput: false,
        handler: () => ({
          kind: 'success',
          text: [
            'dsh-plugin-chatgpt-crash-fix 已加载。',
            '',
            '排查技能: skills/chatgpt-crash-fix/SKILL.md',
            '诊断脚本: scripts/diagnose-chatgpt-crash.ps1',
            '  检查: scripts/check-store-channel.ps1, scripts/check-proxy-config.ps1',
            '  修复: scripts/fix-proxy-bypass.ps1',
            '',
            '请按 SKILL.md 的步骤执行：先定位崩溃转储确认故障模块（常见为',
            'windows-updater.node 访问冲突），再检测微软商店/WU 通道与系统代理，',
            '最后用 fix-proxy-bypass.ps1 添加微软域名绕过列表（会自动备份原设置）。',
            '',
            `资源根目录: ${assetsRoot().href}`,
          ].join('\n'),
        }),
      })
    }
  },
}
