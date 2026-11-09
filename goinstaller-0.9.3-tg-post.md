**goInstaller: goVLESS pro ставится поверх бесплатного Lite, а не открывает его**

Кто ставил бесплатный Lite по инструкции, а потом пришёл в клуб за goVLESS pro, мог получить странное: goInstaller писал «goVLESS pro установлен» и открывал всё тот же Lite. Исправлено и проверено на живом сервере.

**Что было**

Бесплатный Lite ставится в те же папки и под той же командой govless, что и goVLESS pro. goInstaller принимал его за pro: пункт «Открыть меню продукта» запускал Lite. А установщик pro обновлял копию Lite, вместо того чтобы заменить её собой, и снова запускал Lite.

**Что теперь**

— В главном меню против goVLESS pro написано «бесплатный Lite 1.3.6».

— Первый пункт — «Поставить goVLESS pro поверх Lite». Перед установкой goInstaller объясняет, что произойдёт.

— Панель 3X-UI, ключи и пользователи остаются на месте. Клиентам ничего переподключать не нужно: старые ключи работают и после перехода.

— Потом открывается меню goVLESS pro в том же режиме Lite. Оттуда подключается Telegram-бот, там же включается режим Pro со своим доменом и TLS: VPN → «Сменить режим (Lite ↔ Pro)».

Если ставите goVLESS pro его собственной командой из клуба, без goInstaller, исправление тоже работает: установщик pro сам заменит Lite.

**goKaskad pro — то же самое**

Бесплатный Kaskad из инструкции ставил свою команду gokaskad на место pro, и goInstaller открывал бесплатное меню. Теперь goKaskad pro ставится поверх, а ваши правила каскада переходят в его меню и продолжают работать.

**Как обновиться**

Если goinstall уже стоит:

```bash
goinstall --self-update
```

Если ещё нет — та же команда, что и раньше. Вместо КЛЮЧ дважды вставьте ключ из ветки goinstall в anten-ka club:

```bash
GH_TOKEN=КЛЮЧ bash <(curl -fsSL -H "Authorization: token КЛЮЧ" https://raw.githubusercontent.com/duboshin52/goInstaller/main/go-installer.sh)
```

Дальше `goinstall` → goVLESS pro → «Поставить goVLESS pro поверх Lite» → 1.

Нет доступа к клубу? Подписка здесь: https://boosty.to/anten-ka/purchase/3134076?ssource=DIRECT&share=subscription_link
