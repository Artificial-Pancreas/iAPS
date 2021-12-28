# FreeAPS X

FreeAPS X - система искуственной поджелудочной железы для iOS на основе алгоритмов [OpenAPS Reference](https://github.com/openaps/oref0)

FreeAPS X использует оригинальные JavaScript файлы oref0 и предоставляет пользовательский интерфейс (UI) для управления и настроек системы.

## Документация

[Обзор и советы на Loop&Learn](https://www.loopandlearn.org/freeaps-x/)

[Полная документация OpenAPS](https://openaps.readthedocs.io/en/latest/)

## Требования к смартфону

- Все iPhone с поддержкой iOS 15 и выше.

## Поддерживаемые помпы

Для управления инсулиновой помпой используется модифицированная версия библиотеки [rileylink_ios](https://github.com/ps2/rileylink_ios), поддерживает тот же список помп:

- Medtronic 515 or 715 (any firmware)
- Medtronic 522 or 722 (any firmware)
- Medtronic 523 or 723 (firmware 2.4 or lower)
- Medtronic Worldwide Veo 554 or 754 (firmware 2.6A or lower)
- Medtronic Canadian/Australian Veo 554 or 754 (firmware 2.7A or lower)
- Omnipod "Eros" pods

Для управления помпой необходимо устройство [RileyLink](https://getrileylink.org), OrangeLink, Pickle, GNARL, Emalink, DiaLink или аналоги.

## Текущее состояние FreeAPS X

FreeAPS X находится в состоянии активной разработки и часто меняется.

Описание версий вы можете найти на [странице релизов](https://github.com/ivalkou/freeaps/releases).

### Стабильные версии

Стабильная версия означет, что она была протестирована долгое время и не содерждит критических багов. Мы считаем её готовой для повседневного использования.

Номера стабильных версий заканчиваются на **.0**.

### Бета-версии

В бета-версиях впервые появляется новая функциональность. Они предназначены для тестирования и выявления проблем и багов.

**Бета-версии довольно стабильны, но могут содержать случайные ошибки.**

Номера бета-версий заканчиваются на число больше **0**.

## Помощь в разработке

Пулл-реквесты принимаются в [dev ветку](https://github.com/ivalkou/freeaps/tree/dev).

Отчеты об ошибка их запросы на новую функциональность принимаются на странице [Issues](https://github.com/ivalkou/freeaps/issues).

## Реализовано

- Все базовые функции oref0
- Все базовые функции oref1 (SMB, UAM и другие)
- Autotune
- Autosens
- Использование Nightscout в качестве CGM
- Использование оффлайн локального сервера в качестве CGM (программы Spike, Diabox)
- Использование [xDrip4iOS](https://github.com/JohanDegraeve/xdripswift) оффлан в качестве CGM через shared app gpoup
- Использование [GlucoseDirectApp](https://github.com/creepymonster/GlucoseDirectApp) оффлан в качестве CGM через shared app gpoup
- Использование передатчиков Libre 1 и Libre 2 напрямую в качаесте CGM
- Простой симулятор глюкозы
- Загрузка состояния системы в Nightscout
- Удаленный ввод углеводов и временных целей через Nightscout
- Удаленный ввод болюса и управление помпой
- Поддержка Dexcom (beta)
- Поробное описание настроек oref внутри приложения (beta)
- Уведомления на смартфоне о состоянии системы и подключенных к ней устройств (beta)
- Приложение для часов (beta)
- Поддержка Enlite (beta)
- Поддержка программы Здоровье, глюкоза (beta)

## Не реализовано (планируется в будущих версиях)

- Режим открытой петли
- Загрузка профиля в Nightscout
- Виджет на рабочий стол
- Поддержка программы Здоровье, углеводы и инсулин

## Сообщество

- [Английская Telegram группа](https://t.me/freeapsx_eng)
- [Русская Telegram группа](https://t.me/freeapsx)
