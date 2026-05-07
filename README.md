<div align="center">

# [Snowy-Fluffy/zapret.installer](https://github.com/Snowy-Fluffy/zapret.installer)

### Автоматическая установка и удобное управление [bol-van/zapret](https://github.com/bol-van/zapret)

</div>


Облегчает установку zapret для новичков и тех, кто не хочет разбираться в его работе.  
Устанавливает [zapret из оффициального репозитория](https://github.com/bol-van/zapret), CLI панель управления и [репозиторий со стратегиями и списками доменов](https://github.com/Snowy-Fluffy/zapret.cfgs).

### Установка  

Запуск скрипта установки (необходимо наличие *curl* в системе):  
```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Snowy-Fluffy/zapret.installer/refs/heads/main/installer.sh)"
```
Добавляет модуль для zapret в вашу директорию конфигурации, для полноценной установки следуйте инструкциям установщика. Если вы используете flakes то перед ребилдом конфигурации обновите flake.lock.

### NixOS

**Flake (рекомендуется):**

`flake.nix`:
```nix
inputs.zapret.url = "github:kira-we1ss/zapret.installer-nix";

outputs = { self, nixpkgs, zapret, ... }: {
  nixosConfigurations.myhostname = nixpkgs.lib.nixosSystem {
    modules = [
      zapret.nixosModules.default
      ./configuration.nix
    ];
  };
};
```

`configuration.nix`:
```nix
services.zapret.enable = true;
```

**Без flake (стандартные каналы NixOS):**

1. Клонировать репозиторий установщика (однократно, вне управления Nix):
   ```bash
   git clone https://github.com/kira-we1ss/zapret.installer-nix /var/lib/zapret.installer
   ```
2. Скопировать Nix-файлы в `/etc/nixos/`:
   ```bash
   cp /var/lib/zapret.installer/nix/module.nix  /etc/nixos/zapret-module.nix
   cp /var/lib/zapret.installer/nix/package.nix /etc/nixos/zapret-package.nix
   ```
3. В `configuration.nix`:
   ```nix
   imports = [ ./zapret-module.nix ];

   services.zapret.enable = true;
   services.zapret.package = pkgs.callPackage ./zapret-package.nix {
     zapret-src = pkgs.fetchFromGitHub {
       owner = "bol-van";
       repo  = "zapret";
       rev   = "<pinned-commit-sha>";  # конкретный коммит, не "master"
       hash  = "sha256-...";
     };
   };
   # installerSrc по умолчанию /var/lib/zapret.installer — совпадает с путём клона выше
   ```
   Получить актуальный `rev` и `hash`:
   ```bash
   # rev:
   git ls-remote https://github.com/bol-van/zapret HEAD | cut -f1
   # hash:
   nix-prefetch-url --unpack https://github.com/bol-van/zapret/archive/<rev>.tar.gz
   ```

Вызов панели управления:  
```bash
zapret
```

### Поддержка

На данный момент поддерживаются дистрибутивы:  
- Debian, Ubuntu, Mint
- Fedora
- Arch Linux, Artix Linux (и их производные)
- Alt Linux
- Void Linux
- Gentoo Linux
- Redos Linux
- Oracle Linux
- OpenSUSE
- Aipline Linux
- OpenWrt
- NixOS

> [!IMPORTANT]
> На Openwrt также советую попробовать [zapret-openwrt](https://github.com/remittor/zapret-openwrt)

> [!IMPORTANT]
> Системы инициализации *runit*, *OpenRC* и *SysVinit* поддерживаются только частично.

В будущем будет добавлена поддержка других дистрибутивов и систем инициализации.

О всех багах и недочётах сообщайте в [issues](https://github.com/Snowy-Fluffy/zapret.installer/issues) или в чат моего [Telegram-канала](https://t.me/linux_hi_chat).

> [!IMPORTANT]
> Также советую попробовать [zapret-discord-youtube-linux](https://github.com/Sergeydigl3/zapret-discord-youtube-linux)

### Скриншоты
![Основное меню](https://github.com/user-attachments/assets/1b08f280-e435-4f59-aa60-3749e0f25ba0)
![Подменю](https://github.com/user-attachments/assets/27c18e1a-2f6b-4aba-a7df-10f53993b365)


