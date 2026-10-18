# NeverHeardOfVPNs Ratu 1.1.0

Пакет скрывает распространённые локальные признаки VPN в сторонних приложениях и не переключает VPN, маршруты или DNS.

**Ограничения:** обход обычного Ozon не подтверждён: предупреждение оставалось даже при скрытии проверенных локальных признаков. Внешний IP серверу не подменяется. Работа на iOS 26 не проверена; диапазон 17.0–26.0.1 в зависимостях — не свидетельство проверки всех версий. Ozon Селект, по предварительному наблюдению пользователя, пропускал; полной проверки нет.

- Архитектура: iphoneos-arm64; Mach-O содержит arm64 и arm64e PTRAUTH.
- Устройство проверки: iPhone15,3 / iOS 17.0 / Dopamine 3.0.10 / ElleKit 1.2.
- Пакет: [com.thatmarcel.tweaks.neverheardofvpns_1.1.0_iphoneos-arm64.deb](../../debs/com.thatmarcel.tweaks.neverheardofvpns_1.1.0_iphoneos-arm64.deb).
- SHA256: 21292d4cc71a0fd906fc0b47cafd9a1ad96a23ede2ef7d8793e72fef9a691194.
- [Исходный код именно этой сборки](https://github.com/chelaxian/never-heard-of-vpns/tree/af18272).
- [Архив соответствующих исходников](neverheardofvpns-1.1.0-source.tar.gz).
- [Подробные результаты и ограничения](https://github.com/chelaxian/never-heard-of-vpns/blob/ratu-rootless/VALIDATION.md).
- [Оригинал thatmarcel](https://github.com/thatmarcel/never-heard-of-vpns), лицензия AGPL-3.0. Уведомления fishhook BSD сохранены в исходниках и пакете.

Отдельной страницы настроек нет. Для целевого приложения должно быть разрешено внедрение NeverHeardOfVPNs в Choicy. После установки перезапустите целевое приложение. VPN-клиенты с собственным NetworkExtension-провайдером исключены из обработки.
