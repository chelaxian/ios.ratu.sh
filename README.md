# ios.ratu.sh

Personal APT repository for rootless and RootHide jailbreak packages.

Repository URL:

```text
https://ios.ratu.sh/
```

Update package indexes after adding or replacing `.deb` files:

```sh
scripts/build-index.sh
```

Offloader is published in two variants:

- `iphoneos-arm64` for standard rootless jailbreaks such as Dopamine and NathanLR.
- `iphoneos-arm64e` for RootHide Bootstrap.

HPPE remains a RootHide package. It requires the official AlbumManager package
(`com.noisyflake.albummanager`) and extends hidden album asset visibility into
system photo pickers.
