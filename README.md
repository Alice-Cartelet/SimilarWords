# 📚 Swift 英语单词查询与管理应用

一个基于 **SwiftUI** 的英语单词查询工具，支持查找相似词和近义词，并提供本地保存、发音播放和翻译功能。

---

## 🌟 功能特点
<p align="center">
  <img src="https://github.com/user-attachments/assets/6452f59d-146d-4e94-a8ad-09c0d97842d3" alt="描述" width="200" style="margin:0 15%"/>
  <img src="https://github.com/user-attachments/assets/adbc4423-dae9-46bf-afb6-85c3eb2297c7" alt="描述" width="200" style="margin:0 15%"/>
  <img src="https://github.com/user-attachments/assets/75a3f096-0452-42b2-9864-e4f48b59c03e" alt="描述" width="200" style="margin:0 15%"/>
</p>

- **🔍 单词查询** 

  - 输入单词后可查找 **相似词** 或 **近义词**。
  - 相似词通过 **Levenshtein 编辑距离算法**计算相似度。
  - 近义词可通过本地数据匹配，并可调用 **百度翻译 API** 获取外部释义（需自行配置 API）。

- **💾 本地保存**  
  - 支持将查询结果保存至本地。
  - 可按时间或字母排序查看已保存的单词。
  - 支持删除已保存查询。
  -
- **🔊 发音功能**  
  - 支持播放单词的本地音频（位于 `speech/` 目录）。
  - 自动检测音频文件是否存在。

- **🎨 界面交互**  
  - 基于 **SwiftUI** 构建，界面美观、响应流畅。
  - 支持滑动列表、动画提示和搜索历史管理。

- **⚙️ 可自定义相似度阈值**  
  - 通过滑块调整相似词匹配的相似度阈值（0.5~1.0）。

---

## 🛠 技术栈

- Swift 5
- SwiftUI
- CryptoKit（用于 MD5 生成）
- AVFoundation（音频播放）
- 百度翻译 API（可选）

---

## 🚀 使用说明

### 1. 克隆项目并打开 Xcode：
   ```bash
   git clone <你的仓库地址>
   ```

### 2.若需要使用百度翻译，请在 WordManager 中配置 appid 和 key：
  let appid = "你的appid"
  let key = "你的密钥"
将单词发音音频放入 speech/ 文件夹，命名规则为：
单词小写.mp3
运行项目，输入单词即可查询相似词或近义词，并可保存查询。

### 3.当然你也可以直接下载我编译的ipa文件，直接使用。
** 注意⚠ **由于apple的安装限制，需要进行自签名或者使用巨魔安装。

---
## 📄 许可协议
本项目采用 MIT License 开源。
