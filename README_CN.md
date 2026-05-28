# VoiceInk

macOS 菜单栏语音输入法。可选 Apple 本地语音引擎，或任意 OpenAI 兼容转写 API——不污染剪贴板，不锁定供应商。

[English](README.md)

---

## 功能特性

### 双转写引擎

- **Apple Speech** —— 本地、零配置、实时、免费
- **OpenAI 兼容 API** —— 对接任意 OpenAI 兼容的 `/audio/transcriptions` 端点（OpenAI `gpt-4o-mini-transcribe` / `whisper-1`、Groq、自建服务等）
- 短句模式和长文（长文模式）可独立选择引擎

### 大模型纠错

- 利用上下文修正同音字错误（配森→Python，模形→模型，因该→应该）
- 自动去除语气词（嗯/啊/呃/那个）
- 将中文音译自动转换为英文术语
- 支持 OpenAI、Ollama 或任何 OpenAI 兼容 API

### 上下文感知纠错

- 自动维护最近输出的滚动缓冲区，作为下一次 LLM 调用的上下文
- 手动纠正后，纠正结果会替换缓冲区中的原始内容
- 越用越准——正向反馈循环

### 长文模式

- 双击进入长文模式，支持多段录音拼接
- 确认前可预览和编辑
- 独立的 LLM 配置，自动处理口误修正，整理成清晰段落
- 动态浮动面板，实时波形可视化

### 纠正历史与小样本学习

- 转写后短按即可手动纠正错误
- 纠正记录自动保存，作为 LLM 的 few-shot 示例
- 基于 bigram 相似度智能匹配最相关的历史纠正
- 最多保存 200 条纠正记录，完整记录 ASR → LLM → 纠正 的过程

### 用户词典

- 添加专业术语、产品名、专有名词
- 词条同时通过 OpenAI `prompt` 参数注入,引导转写引擎识别
- 词条注入 LLM 系统提示词，作为优先词汇

### 零剪贴板污染

- 通过模拟键盘输入（CGEvent）注入文字，不触碰剪贴板
- 正常使用中永远不会覆盖你的剪贴板内容
- 智能检测 CJK 输入法状态——注入前自动切换英文键盘，完成后恢复

### 多语言支持

简体中文 · English · 繁體中文 · 日本語 · 한국어

### 其他

- **菜单栏应用** —— 无 Dock 图标，占用极小
- **实时波形** —— 录音时实时显示 RMS 波形
- **使用统计** —— 追踪录音次数、时长、纠正次数、长文会话
- **结构化日志** —— 使用 os.Logger 分类，配合 `log stream` 调试

---

## 系统要求

- macOS 14.0+
- 麦克风和辅助功能权限
- （可选）OpenAI 兼容转写 API key —— 仅在选择 OpenAI 引擎时需要;Apple Speech 离线即用，无需配置
- （可选）OpenAI 兼容 API，用于大模型纠错

---

## 构建安装

```bash
git clone https://github.com/Cifer-Y/VoiceInk.git
cd VoiceInk

swift build -c release
cp .build/arm64-apple-macosx/release/VoiceInk VoiceInk.app/Contents/MacOS/VoiceInk
cp -R VoiceInk.app /Applications/
```

---

## 使用方法

1. 启动 VoiceInk —— 出现在菜单栏
2. 根据提示授予麦克风和辅助功能权限
3. 在设置中选择转写引擎 —— Apple Speech 无需配置；OpenAI 需要填 base URL 和 API key
4. **按住右 Option** 录音，松开即转写
5. 转写后 **短按** 可手动纠错
6. **双击** 进入长文模式

---

## 许可证

MIT
