# Аудит существующих Dopamine rootless-пакетов

Дата: 2026-08-18. AppData, AlbumManager и системные RootHide-пакеты исключены. Установка на iPhone не выполнялась.

| Пакет | Результат |
|---|---|
| `com.ratush.hppe` / HPM | Не трогать: актуальная рабочая HPM `1.6.1` поддерживается отдельно; репозиторные `1.5.25`/`1.6.7` не являются device-подтверждением |
| `com.ratush.tgproxyrotation` | **Статический PASS**: rootless `1.0.2` для `iphoneos-arm64` и `iphoneos-arm64e`, исходник без реальных `/rootfs`, `/var/jb`, `.jbroot` |
| `ru.danpashin.twackup` | **Аудит-only**: внешний бинарный rootless `2.0.27`, принадлежащих исходников нет |
| `ru.danpashin.twackup-gui` | **Аудит-only**: внешний бинарный rootless `2.0.27`, arm64 зависит от `libroot-dopamine`, исходников нет |
| `com.ratush.catmcp-rootless-fix` | **Статический PASS с оговоркой**: rootless `1.7.28` чистый; dual-mode исходник собирать только с `THEOS_PACKAGE_SCHEME=rootless` и `control.rootless`, не с Makefile-default `roothide` |
| `com.ratush.iggridfeed` | Rootless `0.5.2+rootless1` опубликован, но каталог `source/Instagram3x3GridFeed` содержит старую RootHide-сборочную конфигурацию; исходник и опубликованный rootless-артефакт нужно синхронизировать перед следующей правкой |
| `com.ratush.vpnappbridge` | Rootless-папка существует, но пакет жёстко зависит от отсутствующего `com.snail.autovpn.global`; миграция заблокирована внешней зависимостью |

## Ограничения

- Rootless payload не должен содержать `.roothidepatch` или `DynamicPatches/AutoPatches.dylib`.
- `/rootfs` нельзя использовать; `/var/jb` допускается только как runtime-путь Dopamine.
- WSL/Linux-сборка standalone arm64e не считается доказательством совместимости; нужен macOS/Xcode PTRAUTH gate и затем runtime-тест.
- Runtime ни одного перечисленного пакета в этой процедуре не проверялся.

## Решение

TGProxyRotation и CatMCP уже имеют опубликованные rootless-артефакты; повторная публикация не требуется. Twackup/Twackup GUI остаются внешними бинарными пакетами. HPM не изменяется. Offloader, AutoVPN base, AppData, AlbumManager и системные RootHide-пакеты без принадлежащего исходника не портируются.
