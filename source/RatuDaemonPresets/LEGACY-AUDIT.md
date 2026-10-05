# Appcd и Cappd: проверка для iOS 17.0

Пакеты Appcd распакованы через dpkg-deb. Скрипты не запускались на телефоне. Источник: https://github.com/f0xforce/appcd

| Служба | LITE | Medium | MAX | Есть на устройстве | Решение |
|---|---|---|---|---|---|
| com.apple.DumpBasebandCrash | ✓ | ✓ | ✓ | да | Не переносится: диагностика сотового модема |
| com.apple.DumpPanic | — | ✓ | ✓ | да | Не переносится: диагностика паник |
| com.apple.OTACrashCopier | ✓ | ✓ | ✓ | да | Не переносится: диагностика |
| com.apple.OTATaskingAgent | ✓ | ✓ | ✓ | да | Не переносится: диагностические задания |
| com.apple.ReportCrash | — | ✓ | ✓ | да | Не переносится: диагностика сбоев нужна для восстановления |
| com.apple.ReportCrash.DirectoryService | — | ✓ | ✓ | нет | Отсутствует на iOS 17 в этом имени; замена по догадке не делается |
| com.apple.ReportCrash.Jetsam | — | ✓ | ✓ | нет | Отсутствует на iOS 17 в этом имени; замена по догадке не делается |
| com.apple.ReportCrash.SafetyNet | — | ✓ | ✓ | нет | Отсутствует на iOS 17 в этом имени; замена по догадке не делается |
| com.apple.ReportCrash.StackShot | — | ✓ | ✓ | нет | Отсутствует на iOS 17 в этом имени; замена по догадке не делается |
| com.apple.WebBookmarks.webbookmarksd | ✓ | ✓ | ✓ | да | Заблокирована: закладки, фильтр веб-контента и другие задачи |
| com.apple.ap.adtrackingd | ✓ | ✓ | ✓ | нет | Отсутствует на iOS 17 в этом имени; замена по догадке не делается |
| com.apple.aslmanager | ✓ | ✓ | ✓ | да | Не переносится: старое обслуживание журналов; польза не доказана |
| com.apple.assistivetouchd | ✓ | ✓ | ✓ | да | Не переносится в пресет: доступность / AssistiveTouch |
| com.apple.atkwakeup | ✓ | ✓ | ✓ | нет | Отсутствует на iOS 17 в этом имени; замена по догадке не делается |
| com.apple.coreservices.lsactivity | ✓ | ✓ | ✓ | нет | Отсутствует на iOS 17 в этом имени; замена по догадке не делается |
| com.apple.healthd | — | — | ✓ | да | Не переносится: Здоровье |
| com.apple.homed | — | — | ✓ | да | Не переносится: HomeKit / Дом |
| com.apple.nanobackupd | ✓ | ✓ | ✓ | да | Добавлена: только без Apple Watch |
| com.apple.softwareupdateservicesd | ✓ | — | ✓ | да | Не переносится: обновления системы |
| com.apple.tipsd | ✓ | ✓ | ✓ | да | Добавлена: отключается обновление Советов |
| com.apple.videosubscriptionsd | ✓ | ✓ | ✓ | да | Добавлена условно: потеря функций ТВ-провайдера |

В этих конкретных архивах нет команды отключения locationd. Сообщения пользователей о геолокации не доказывают наличия locationd в списке. Lite содержит 13 целей, Medium — 18, MAX — 21. Medium не является строгим надмножеством Lite: softwareupdateservicesd имеется в Lite/MAX, отсутствует в Medium.

Во всех трёх postinst используется `bash /etc/rc.d/<набор>/*`. Bash исполняет первый файл, остальные передаются как аргументы. Это не цикл выполнения всех сгенерированных скриптов. Поэтому сообщение автора об успешном отключении всех демонов само по себе не доказательство. В postrm Lite удаляется каталог скриптов, но исходные состояния launchd не восстанавливаются.

Для нашего проекта старые rootful команды и запись в /etc/rc.d не используются. Управление: rootless launchctl disable + bootout, подтверждение состояния, журнал и восстановление. Сам код Appcd не копировался.

Cappd: доступная карточка 1.0.3 подтверждает метаданные, но не содержимое архива. Источник https://www.ios-repo-updates.com/repository/dpkg9510-s-repository/package/com.dpkg.cappd/. Исторический обзор опубликован 17.01.2019, поэтому считать его точным анализом версии 1.0.3 от 01.04.2019 нельзя. Исходный DEB недоступен; 1:1 команды Cappd не восстановлены.

Из приведённого списка Cappd на устройстве найдены videosubscriptionsd, askpermissiond, nanobackupd, tipsd, WebBookmarks.webbookmarksd. ad.adtrackingd / ap.adtrackingd, coreservices.lsactivity и SafariCloudHistoryPushAgent не найдены.

Выборочный пресет Cappd / Appcd включает tipsd, videosubscriptionsd, nanobackupd. askpermissiond доступен отдельно с предупреждением о семейных запросах покупок. Базовый пресет отчёта не расширяется автоматически.

Связь назначения подтверждается plist служб и документацией Apple: https://developer.apple.com/documentation/videosubscriberaccount, https://support.apple.com/en-us/105055, https://support.apple.com/en-us/108358. Документация функций не означает сертификацию отключения приватных демонов Apple.
