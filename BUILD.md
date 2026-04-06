# Azimuth — Інструкція зі збірки

## Передумови

### Java JDK
Garmin Connect IQ SDK потребує Java 8 або новіше.

| ОС | Рекомендація |
|----|-------------|
| Linux | `sudo apt install openjdk-17-jdk` (Debian/Ubuntu) або `sudo dnf install java-17-openjdk` (Fedora) |
| macOS | `brew install openjdk@17` або завантажити з [adoptium.net](https://adoptium.net) |
| Windows | Завантажити з [adoptium.net](https://adoptium.net), встановити, додати до PATH |

Перевірка: `java -version`

---

## 1. Встановлення Connect IQ SDK

### Linux

```bash
# 1. Завантажити SDK з https://developer.garmin.com/connect-iq/sdk/
#    Файл: connectiq-sdk-lin-X.X.X-XXXX.zip

unzip connectiq-sdk-lin-*.zip -d ~/garmin-sdk

# 2. Додати до PATH (додати в ~/.bashrc або ~/.zshrc)
export CIQ_HOME="$HOME/garmin-sdk"
export PATH="$CIQ_HOME/bin:$PATH"

source ~/.bashrc   # або source ~/.zshrc
```

### macOS

```bash
# 1. Завантажити SDK з https://developer.garmin.com/connect-iq/sdk/
#    Файл: connectiq-sdk-mac-X.X.X-XXXX.zip

unzip connectiq-sdk-mac-*.zip -d ~/garmin-sdk

# 2. Додати до PATH (додати в ~/.zshrc)
export CIQ_HOME="$HOME/garmin-sdk"
export PATH="$CIQ_HOME/bin:$PATH"

source ~/.zshrc

# 3. Дозволити запуск (Gatekeeper)
xattr -dr com.apple.quarantine ~/garmin-sdk/bin/monkeyc
xattr -dr com.apple.quarantine ~/garmin-sdk/bin/connectiq
```

### Windows

1. Завантажити SDK: `connectiq-sdk-win-X.X.X-XXXX.zip`
2. Розпакувати, наприклад, до `C:\garmin-sdk`
3. Додати до системного PATH:
   - Панель керування → Система → Додаткові параметри системи → Змінні середовища
   - У розділі "Системні змінні" знайти `Path`, натиснути "Змінити"
   - Додати: `C:\garmin-sdk\bin`
4. Перезапустити термінал

Перевірка: `monkeyc --version`

---

## 2. Генерація ключа розробника (одноразово)

Ключ потрібен для підпису збірок. Виконується один раз.

### Linux / macOS

```bash
cd /Users/ak/Downloads/Claude/Azimuth

# Генерація приватного ключа
openssl genrsa -out developer_key.pem 4096

# Конвертація у формат DER (потрібен для monkeyc)
openssl pkcs8 -topk8 -inform PEM -outform DER \
    -in developer_key.pem -out developer_key.der -nocrypt
```

### Windows (PowerShell або Git Bash з OpenSSL)

```powershell
cd C:\path\to\Azimuth

openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER `
    -in developer_key.pem -out developer_key.der -nocrypt
```

> **Увага:** `developer_key.pem` і `developer_key.der` — приватні! Не додавайте до git-репозиторію.

---

## 3. Збірка проєкту

### Підтримувані пристрої

ID пристроїв з `manifest.xml`:

```
fenix7        fenix7s       fenix7x
fenix7pro     fenix7spro    fenix7xpro
fenix8        fenix8solar   fenix8amoled
fr265         fr265s        fr965
epix2         epix2pro42    epix2pro47  epix2pro51
instinct2     instinct2s    instinct2x
instinct3amoled50  instinct3amoled45
instinct3solar50   instinct3solar45
venu3         venu3s
vivoactive5
d2mach1
```

### Збірка для конкретного пристрою

```bash
cd /Users/ak/Downloads/Claude/Azimuth

monkeyc \
    -f monkey.jungle \
    -o Azimuth.prg \
    -d fenix7 \
    -y developer_key.der
```

Замініть `fenix7` на потрібний ID пристрою зі списку вище.

### Збірка для всіх пристроїв (IQ-пакет для Connect IQ Store)

```bash
monkeyc \
    -f monkey.jungle \
    -o Azimuth.iq \
    -e \
    -y developer_key.der
```

Прапор `-e` будує `.iq` файл з підтримкою всіх пристроїв із `manifest.xml`.

---

## 4. Запуск у симуляторі

### Запуск симулятора

```bash
# Запустити Connect IQ симулятор (у фоні)
connectiq &
```

### Завантаження програми в симулятор

```bash
monkeydo Azimuth.prg fenix7
```

Симулятор відкриється з програмою на вибраному пристрої. Використовуйте кнопки симулятора для навігації.

### Симуляція GPS у симуляторі

У симуляторі: **Simulation → Generate Position** — ввести координати вручну, або завантажити GPX-файл через **Simulation → Simulate GPS Track**.

---

## 5. Розгортання на пристрій

### Через USB

1. Підключити годинник до ПК через USB
2. Годинник з'явиться як флеш-накопичувач
3. Скопіювати `.prg` файл до папки `GARMIN/APPS/` на пристрої
4. Безпечно від'єднати пристрій

### Через Garmin Express / Connect IQ Store

Для публікації використовується `.iq` файл, завантажений через [apps.garmin.com/developer](https://apps.garmin.com/developer).

---

## 6. Повна команда збірки (приклад скрипту)

### Linux / macOS (`build.sh`)

```bash
#!/bin/bash
set -e

DEVICE="${1:-fenix7}"
KEY="developer_key.der"
OUTPUT="Azimuth.prg"

echo "Збірка для: $DEVICE"
monkeyc -f monkey.jungle -o "$OUTPUT" -d "$DEVICE" -y "$KEY"
echo "Готово: $OUTPUT"

# Якщо є симулятор — запустити
if command -v monkeydo &>/dev/null; then
    echo "Запуск у симуляторі..."
    monkeydo "$OUTPUT" "$DEVICE"
fi
```

```bash
chmod +x build.sh
./build.sh fenix7        # збірка для fenix7
./build.sh fr265         # збірка для fr265
```

### Windows (`build.bat`)

```bat
@echo off
SET DEVICE=%1
IF "%DEVICE%"=="" SET DEVICE=fenix7

echo Збірка для: %DEVICE%
monkeyc -f monkey.jungle -o Azimuth.prg -d %DEVICE% -y developer_key.der
echo Готово: Azimuth.prg
```

```bat
build.bat fenix7
build.bat fr265
```

---

## 7. Вирішення проблем

| Проблема | Рішення |
|----------|---------|
| `monkeyc: command not found` | Перевірте PATH, перезапустіть термінал |
| `Error: Could not find device` | Перевірте ID пристрою у `manifest.xml` |
| `Invalid developer key` | Перегенеруйте ключ (розділ 2) |
| `Java not found` | Встановіть JDK 8+ і перевірте `JAVA_HOME` |
| macOS: `permission denied` | Виконайте `xattr -dr com.apple.quarantine ~/garmin-sdk/bin/*` |
| Симулятор не бачить GPS | У симуляторі: Simulation → Enable Location Services |

---

## Структура проєкту

```
Azimuth/
├── manifest.xml              # метадані, дозволи, пристрої
├── monkey.jungle             # конфігурація збірки, мовні ресурси
├── developer_key.der         # ключ підпису (НЕ в git!)
├── source/
│   ├── AzimuthApp.mc         # точка входу
│   ├── AzimuthView.mc        # головний екран
│   ├── AzimuthDelegate.mc    # обробник кнопок
│   ├── AzimuthMenuDelegate.mc
│   ├── AddObjectDelegate.mc
│   ├── DeleteObjectDelegate.mc
│   ├── CoordInputView.mc     # введення MGRS-координат
│   ├── NamePickerDelegate.mc # введення назви точки
│   ├── CustomObjects.mc      # збереження точок у Storage
│   ├── MGRSUtil.mc           # конвертація MGRS ↔ lat/lon
│   └── L.mc                  # helper для локалізованих рядків
├── resources/                # English (default)
│   └── strings/strings.xml
├── resources-ukr/            # Українська
├── resources-fra/            # Français
├── resources-deu/            # Deutsch
├── resources-pol/            # Polski
└── resources-bel/            # Беларуская
```
