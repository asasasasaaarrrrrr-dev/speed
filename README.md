# Montex Speed (SwiftUI)

Минималистичное iOS-приложение в стиле Liquid Glass: реальный GPS-спидометр, 2D-датчик перегрузок (G-Force), замер разгона 0–100 / 100–200, проекционный режим HUD и реальный спидтест сети (Ping / Jitter / Download / Upload). Без симуляции и фейковых данных.

## Сборка в Xcode (macOS)
1. Установите XcodeGen (`brew install xcodegen`).
2. В папке проекта выполните:
   ```bash
   xcodegen generate
   open MontexSpeed.xcodeproj
   ```
3. Выберите свой Team в **Signing & Capabilities** и запустите на iPhone.

## Сборка `.ipa` через GitHub Actions (без Mac)
1. Загрузите содержимое папки `MontexSpeed` в свой репозиторий на GitHub.
2. Откройте вкладку **Actions** -> **Build Unsigned IPA** -> **Run workflow**.
3. Скачайте готовый `MontexSpeed.ipa` из артефактов сборки.
