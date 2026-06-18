# RootHide iOS Dev Arsenal Mirror

Snapshot date: 2026-06-18
Source device: iPhone 14 Pro Max, iOS 17.0, RootHide Bootstrap 2.2
Purpose: emergency mirror of packages used for jailbreak tweak development, deployment, diagnostics, SSH access, Frida runtime inspection, package patching, and command-line recovery.

This is a curated RootHide/iphoneos-arm64e development set with dependency closure verified locally before publishing. It intentionally excludes paid/proprietary user-facing tweaks such as Filza/iCleaner and excludes old intermediate test builds from /var/mobile.

Dependency sanity check before publishing: PACKAGE_COUNT=92, MISSING_COUNT=0 for the mirrored dev stack.

## Packages

| Package | Version | Architecture | File |
|---|---:|---|---|
| apt | 2.6.0-2 | iphoneos-arm64e | apt_2.6.0-2_iphoneos-arm64e.deb |
| apt-utils | 2.6.0-2 | iphoneos-arm64e | apt-utils_2.6.0-2_iphoneos-arm64e.deb |
| bash | 5.2.15 | iphoneos-arm64e | bash_5.2.15_iphoneos-arm64e.deb |
| ca-certificates | 20231210 | all | ca-certificates_20231210_all.deb |
| chariz-keyring | 2021.07.18 | all | chariz-keyring_2021.07.18_all.deb |
| com.roothide.patcher | 2.1.4-1+debug | iphoneos-arm64e | com.roothide.patcher_2.1.4-1+debug_iphoneos-arm64e.deb |
| com.roothide.patchloader | 0.0.8 | iphoneos-arm64e | com.roothide.patchloader_0.0.8_iphoneos-arm64e.deb |
| coreutils | 9.3-1 | iphoneos-arm64e | coreutils_9.3-1_iphoneos-arm64e.deb |
| darwintools | 1.6 | iphoneos-arm64e | darwintools_1.6_iphoneos-arm64e.deb |
| dash | 0.5.12 | iphoneos-arm64e | dash_0.5.12_iphoneos-arm64e.deb |
| debianutils | 5.7-1 | iphoneos-arm64e | debianutils_5.7-1_iphoneos-arm64e.deb |
| diffutils | 3.8 | iphoneos-arm64e | diffutils_3.8_iphoneos-arm64e.deb |
| dpkg | 1.21.21 | iphoneos-arm64e | dpkg_1.21.21_iphoneos-arm64e.deb |
| ellekit | 1.1.3-3 | iphoneos-arm64e | ellekit_1.1.3-3_iphoneos-arm64e.deb |
| file | 5.43 | iphoneos-arm64e | file_5.43_iphoneos-arm64e.deb |
| file-cmds | 400-1 | iphoneos-arm64e | file-cmds_400-1_iphoneos-arm64e.deb |
| findutils | 4.8.0-1 | iphoneos-arm64e | findutils_4.8.0-1_iphoneos-arm64e.deb |
| gawk | 5.1.0-2 | iphoneos-arm64e | gawk_5.1.0-2_iphoneos-arm64e.deb |
| gpgv | 2.3.6 | iphoneos-arm64e | gpgv_2.3.6_iphoneos-arm64e.deb |
| grep | 3.10-1 | iphoneos-arm64e | grep_3.10-1_iphoneos-arm64e.deb |
| gzip | 1.12 | iphoneos-arm64e | gzip_1.12_iphoneos-arm64e.deb |
| havoc-keyring | 2022.06.03 | all | havoc-keyring_2022.06.03_all.deb |
| htop | 3.2.2 | iphoneos-arm64e | htop_3.2.2_iphoneos-arm64e.deb |
| launchctl | 1:1.1.1-2 | iphoneos-arm64e | launchctl_1%3a1.1.1-2_iphoneos-arm64e.deb |
| ldid | 2.1.5-procursus7 | iphoneos-arm64e | ldid_2.1.5-procursus7_iphoneos-arm64e.deb |
| libapt-pkg6.0 | 2.6.0-2 | iphoneos-arm64e | libapt-pkg6.0_2.6.0-2_iphoneos-arm64e.deb |
| libassuan0 | 2.5.5 | iphoneos-arm64e | libassuan0_2.5.5_iphoneos-arm64e.deb |
| libbrotli1 | 1.0.9 | iphoneos-arm64e | libbrotli1_1.0.9_iphoneos-arm64e.deb |
| libcrypt2 | 4.4.33 | iphoneos-arm64e | libcrypt2_4.4.33_iphoneos-arm64e.deb |
| libdb18.1 | 18.1.40-1 | iphoneos-arm64e | libdb18.1_18.1.40-1_iphoneos-arm64e.deb |
| libedit0 | 3.1-20221030 | iphoneos-arm64e | libedit0_3.1-20221030_iphoneos-arm64e.deb |
| libffi8 | 3.4.2 | iphoneos-arm64e | libffi8_3.4.2_iphoneos-arm64e.deb |
| libgcrypt20 | 1.10.1 | iphoneos-arm64e | libgcrypt20_1.10.1_iphoneos-arm64e.deb |
| libgdbm6 | 1.19 | iphoneos-arm64e | libgdbm6_1.19_iphoneos-arm64e.deb |
| libgmp10 | 6.2.1-3 | iphoneos-arm64e | libgmp10_6.2.1-3_iphoneos-arm64e.deb |
| libgnutls30 | 3.8.0 | iphoneos-arm64e | libgnutls30_3.8.0_iphoneos-arm64e.deb |
| libgpg-error0 | 1.46 | iphoneos-arm64e | libgpg-error0_1.46_iphoneos-arm64e.deb |
| libhogweed6 | 3.8.1 | iphoneos-arm64e | libhogweed6_3.8.1_iphoneos-arm64e.deb |
| libidn2-0 | 2.3.4 | iphoneos-arm64e | libidn2-0_2.3.4_iphoneos-arm64e.deb |
| libintl8 | 0.21.1 | iphoneos-arm64e | libintl8_0.21.1_iphoneos-arm64e.deb |
| libiosexec1 | 1.3.1-2 | iphoneos-arm64e | libiosexec1_1.3.1-2_iphoneos-arm64e.deb |
| liblz4-1 | 1.9.3 | iphoneos-arm64e | liblz4-1_1.9.3_iphoneos-arm64e.deb |
| liblzma5 | 5.4.1 | iphoneos-arm64e | liblzma5_5.4.1_iphoneos-arm64e.deb |
| libmagic1 | 5.43 | iphoneos-arm64e | libmagic1_5.43_iphoneos-arm64e.deb |
| libmd0 | 1.0.4-1 | iphoneos-arm64e | libmd0_1.0.4-1_iphoneos-arm64e.deb |
| libmpfr6 | 4.1.0 | iphoneos-arm64e | libmpfr6_4.1.0_iphoneos-arm64e.deb |
| libncursesw6 | 6.4 | iphoneos-arm64e | libncursesw6_6.4_iphoneos-arm64e.deb |
| libnettle8 | 3.8.1 | iphoneos-arm64e | libnettle8_3.8.1_iphoneos-arm64e.deb |
| libnpth0 | 1.6-2 | iphoneos-arm64e | libnpth0_1.6-2_iphoneos-arm64e.deb |
| libp11-kit0 | 0.24.1 | iphoneos-arm64e | libp11-kit0_0.24.1_iphoneos-arm64e.deb |
| libpam-modules | 1000.0 | iphoneos-arm64e | libpam-modules_1000.0_iphoneos-arm64e.deb |
| libpam2 | 20190224 | iphoneos-arm64e | libpam2_20190224_iphoneos-arm64e.deb |
| libpcapa | 1.10.1-1 | iphoneos-arm64e | libpcapa_1.10.1-1_iphoneos-arm64e.deb |
| libpcre1 | 8.45-1 | iphoneos-arm64e | libpcre1_8.45-1_iphoneos-arm64e.deb |
| libpcre2-8-0 | 10.40-1 | iphoneos-arm64e | libpcre2-8-0_10.40-1_iphoneos-arm64e.deb |
| libplist3 | 2.2.0+git20230130.4b50a5a | iphoneos-arm64e | libplist3_2.2.0+git20230130.4b50a5a_iphoneos-arm64e.deb |
| libpython3.9 | 3.9.9-2 | iphoneos-arm64e | libpython3.9_3.9.9-2_iphoneos-arm64e.deb |
| libreadline8 | 8.2.0-1 | iphoneos-arm64e | libreadline8_8.2.0-1_iphoneos-arm64e.deb |
| libssl3 | 3.0.8 | iphoneos-arm64e | libssl3_3.0.8_iphoneos-arm64e.deb |
| libtasn1-6 | 4.18.0 | iphoneos-arm64e | libtasn1-6_4.18.0_iphoneos-arm64e.deb |
| libunistring5 | 1.1 | iphoneos-arm64e | libunistring5_1.1_iphoneos-arm64e.deb |
| libxar1 | 1.8.0.487.100.1-1 | iphoneos-arm64e | libxar1_1.8.0.487.100.1-1_iphoneos-arm64e.deb |
| libxxhash0 | 0.8.1 | iphoneos-arm64e | libxxhash0_0.8.1_iphoneos-arm64e.deb |
| libz-ng2 | 2.0.6 | iphoneos-arm64e | libz-ng2_2.0.6_iphoneos-arm64e.deb |
| libzstd1 | 1.5.5 | iphoneos-arm64e | libzstd1_1.5.5_iphoneos-arm64e.deb |
| nano | 7.2 | iphoneos-arm64e | nano_7.2_iphoneos-arm64e.deb |
| ncurses-term | 6.4 | all | ncurses-term_6.4_all.deb |
| network-cmds | 641-1 | iphoneos-arm64e | network-cmds_641-1_iphoneos-arm64e.deb |
| openssh | 1:0 | iphoneos-arm64e | openssh_1%3a0_iphoneos-arm64e.deb |
| openssh-client | 9.2p1 | iphoneos-arm64e | openssh-client_9.2p1_iphoneos-arm64e.deb |
| openssh-server | 9.2p1 | iphoneos-arm64e | openssh-server_9.2p1_iphoneos-arm64e.deb |
| openssh-sftp-server | 9.2p1 | iphoneos-arm64e | openssh-sftp-server_9.2p1_iphoneos-arm64e.deb |
| openssl | 3.0.8 | iphoneos-arm64e | openssl_3.0.8_iphoneos-arm64e.deb |
| p7zip | 17.04 | iphoneos-arm64e | p7zip_17.04_iphoneos-arm64e.deb |
| plutil | 0.2.2+2 | iphoneos-arm64e | plutil_0.2.2+2_iphoneos-arm64e.deb |
| preferenceloader | 2.2.6-11+debug | iphoneos-arm64e | preferenceloader_2.2.6-11+debug_iphoneos-arm64e.deb |
| procursus-keyring | 2020.05.09-4 | all | procursus-keyring_2020.05.09-4_all.deb |
| profile.d | 0-7 | iphoneos-arm64e | profile.d_0-7_iphoneos-arm64e.deb |
| python3 | 3.9.9-2 | iphoneos-arm64e | python3_3.9.9-2_iphoneos-arm64e.deb |
| python3.9 | 3.9.9-2 | iphoneos-arm64e | python3.9_3.9.9-2_iphoneos-arm64e.deb |
| re.frida.server | 16.1.4 | iphoneos-arm64e | re.frida.server_16.1.4_iphoneos-arm64e.deb |
| roothide | 0.1.0 | iphoneos-arm64e | roothide_0.1.0_iphoneos-arm64e.deb |
| sed | 4.9 | iphoneos-arm64e | sed_4.9_iphoneos-arm64e.deb |
| shell-cmds | 278-2 | iphoneos-arm64e | shell-cmds_278-2_iphoneos-arm64e.deb |
| system-cmds | 950-2 | iphoneos-arm64e | system-cmds_950-2_iphoneos-arm64e.deb |
| tar | 1.34 | iphoneos-arm64e | tar_1.34_iphoneos-arm64e.deb |
| uikittools | 2.1.6-4 | iphoneos-arm64e | uikittools_2.1.6-4_iphoneos-arm64e.deb |
| unzip | 6.0-28 | iphoneos-arm64e | unzip_6.0-28_iphoneos-arm64e.deb |
| wget | 1.21.3-1 | iphoneos-arm64e | wget_1.21.3-1_iphoneos-arm64e.deb |
| xz-utils | 5.4.1 | iphoneos-arm64e | xz-utils_5.4.1_iphoneos-arm64e.deb |
| zip | 3.0-12 | iphoneos-arm64e | zip_3.0-12_iphoneos-arm64e.deb |
| zsh | 5.9 | iphoneos-arm64e | zsh_5.9_iphoneos-arm64e.deb |
