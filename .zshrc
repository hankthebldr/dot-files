
    * You will not see this error message again.
    * Zsh will start slowly.

  - Do nothing.

    * You will see this error message every time you start zsh.
    * Zsh will start quickly but prompt will jump down after initialization.

For details, see:
https://github.com/romkatv/powerlevel10k/blob/master/README.md#instant-prompt

-- console output produced during zsh initialization follows --

[oh-my-zsh] plugin 'web-searc' not found
    ~ ············································································································ at 09:08:16 AM  ─╮
❯ ps aux | grep screensharingsubscribe                                                                                                   ─╯
henry            10868   0.0  0.0 410059936    336 s000  R+    9:08AM   0:00.00 grep --color=auto --exclude-dir=.bzr --exclude-dir=CVS --exclude-dir=.git --exclude-dir=.hg --exclude-dir=.svn --exclude-dir=.idea --exclude-dir=.tox --exclude-dir=.venv --exclude-dir=venv screensharingsubscribe

    ~ ············································································································ at 09:08:19 AM  ─     ~ ············································································································ at 09:08:19 AM     ~    ~ ·············································································································· at    ~ ··    ~ ············································································································ at 09:08:19 AM  ─╮
❯ clear                                                                                                                                  ─╯














    ~ ············································································································ at 02:58:36 PM  ─╮
❯ brew upgrade                                                                                                                           ─╯
==> Auto-updating Homebrew...
Adjust how often this is run with HOMEBREW_AUTO_UPDATE_SECS or disable with
HOMEBREW_NO_AUTO_UPDATE. Hide these hints with HOMEBREW_NO_ENV_HINTS (see `man brew`).
==> Auto-updated Homebrew!
Updated 3 taps (homebrew/services, homebrew/core and homebrew/cask).
==> New Formulae
aqua           cspell         dyff           havener        infisical      pkl-lsp        soft-serve     visidata       zns
bombardier     dbg-macro      fastly         hk             nak            sitefetch      sv2v           wfa2-lib
cot            dtsroll        foundry        hl             pdfly          snowflake-cli  taskflow       xk6
==> New Casks
batfi                              font-boldonse                      granola                            obscura-vpn
font-aporetic                      font-bytesized                     istatistica-core                   pdl

You have 17 outdated formulae installed.

==> Upgrading 17 outdated packages:
openshift-cli 4.17.15 -> 4.17.16
hwloc 2.11.2 -> 2.12.0
tree-sitter 0.24.7 -> 0.25.2
docker 27.5.1 -> 28.0.0
libpng 1.6.46 -> 1.6.47
docker-completion 27.5.1 -> 28.0.0
harfbuzz 10.2.0 -> 10.3.0
openssh 9.9p1 -> 9.9p2
libassuan 3.0.1 -> 3.0.2
sqlite 3.49.0 -> 3.49.1
emacs 29.4_1 -> 29.4_2
snort 3.6.3.0 -> 3.7.0.0
zstd 1.5.6 -> 1.5.7
socat 1.8.0.2 -> 1.8.0.3
jenkins 2.497 -> 2.498
docker-compose 2.33.0 -> 2.33.1
fzf 0.60.0 -> 0.60.2
==> Downloading https://ghcr.io/v2/homebrew/core/sqlite/manifests/3.49.1
##################################################################################################################################### 100.0%
==> Fetching sqlite
==> Downloading https://ghcr.io/v2/homebrew/core/sqlite/blobs/sha256:757c3d60f4d35fe1c3336207d63992fc804fa6ddd2c40ebb84eb7bfa07bc69e1
##################################################################################################################################### 100.0%
==> Downloading https://ghcr.io/v2/homebrew/core/hwloc/manifests/2.12.0
##################################################################################################################################### 100.0%
==> Fetching hwloc
==> Downloading https://ghcr.io/v2/homebrew/core/hwloc/blobs/sha256:abc5173fdb1e8441a701efb7d3ae8f9214952cbf16e5da71d5a0f9656a0702ed
##################################################################################################################################### 100.0%
==> Downloading https://ghcr.io/v2/homebrew/core/tree-sitter/manifests/0.25.2
##################################################################################################################################### 100.0%
==> Fetching tree-sitter
==> Downloading https://ghcr.io/v2/homebrew/core/tree-sitter/blobs/sha256:4207c6a66590dcdff74255b2f2f707a7018d4c96dbb46f92251dfad5113c0b2c
##################################################################################################################################### 100.0%
==> Downloading https://ghcr.io/v2/homebrew/core/docker-completion/manifests/28.0.0
##################################################################################################################################### 100.0%
==> Fetching docker-completion
==> Downloading https://ghcr.io/v2/homebrew/core/docker-completion/blobs/sha256:177f990f166a27dcbf422e21b99dea12e23e607487ac0518d865e86f62dd
##################################################################################################################################### 100.0%
==> Downloading https://ghcr.io/v2/homebrew/core/docker/manifests/28.0.0
##################################################################################################################################### 100.0%
==> Fetching docker
==> Downloading https://ghcr.io/v2/homebrew/core/docker/blobs/sha256:cd998255908222eb848970f978a0ee57f3a63fc8e81e56a7756ccd38088bc535
##################################################################################################################################### 100.0%
==> Downloading https://ghcr.io/v2/homebrew/core/libpng/manifests/1.6.47
##################################################################################################################################### 100.0%
==> Fetching libpng
==> Downloading https://ghcr.io/v2/homebrew/core/libpng/blobs/sha256:b4a7f252793b6a2d9d111cecaf5f0c91fd91d9c1c174a8796a487621a05f6f24
##################################################################################################################################### 100.0%
==> Downloading https://ghcr.io/v2/homebrew/core/harfbuzz/manifests/10.3.0
##################################################################################################################################### 100.0%
==> Fetching harfbuzz
==> Downloading https://ghcr.io/v2/homebrew/core/harfbuzz/blobs/sha256:dda9be15e9537e696e55cda8bd9d7b2250bd200441e7d4ca3b13dc84fd770944
##################################################################################################################################### 100.0%
==> Downloading https://ghcr.io/v2/homebrew/core/openssh/manifests/9.9p2
##################################################################################################################################### 100.0%
==> Fetching openssh
==> Downloading https://ghcr.io/v2/homebrew/core/openssh/blobs/sha256:0f9bafc94fa471cbb2385c7d6c94555007562649922e994db8c0445a509f7309
##################################################################################################################################### 100.0%
==> Downloading https://ghcr.io/v2/homebrew/core/libassuan/manifests/3.0.2
##################################################################################################################################### 100.0%
==> Fetching libassuan
==> Downloading https://ghcr.io/v2/homebrew/core/libassuan/blobs/sha256:1430611fe9f337d6a7568a12321f125c567ca8d4d2bdcd7ff0717bdcd82a32dc
##################################################################################################################################### 100.0%
==> Downloading https://ghcr.io/v2/homebrew/core/emacs/manifests/29.4_2
##################################################################################################################################### 100.0%
==> Fetching emacs
==> Downloading https://ghcr.io/v2/homebrew/core/emacs/blobs/sha256:a35f383006a8934c58a3f45947533572b4a69d8b7694e81324a0d86be5cb0061
##################################################################################################################################### 100.0%
==> Downloading https://ghcr.io/v2/homebrew/core/snort/manifests/3.7.0.0
##################################################################################################################################### 100.0%
==> Fetching snort
==> Downloading https://ghcr.io/v2/homebrew/core/snort/blobs/sha256:ec2b112c4b705fa0f5216e5832acd4aa19998a54312d3e9f5998e69f14e1292f
##################################################################################################################################### 100.0%
==> Downloading https://ghcr.io/v2/homebrew/core/zstd/manifests/1.5.7
##################################################################################################################################### 100.0%
==> Fetching zstd
==> Downloading https://ghcr.io/v2/homebrew/core/zstd/blobs/sha256:b039c851ef22617804576274872c33727ebb3a0b5e0db2ab62e0d8a97ec9605a
##################################################################################################################################### 100.0%
==> Downloading https://ghcr.io/v2/homebrew/core/socat/manifests/1.8.0.3
##################################################################################################################################### 100.0%
==> Fetching socat
==> Downloading https://ghcr.io/v2/homebrew/core/socat/blobs/sha256:2aaa10446c3d48a4abae274444c3ab9de518616dec42dde68146220d1cc58cf9
##################################################################################################################################### 100.0%
==> Downloading https://ghcr.io/v2/homebrew/core/jenkins/manifests/2.498
##################################################################################################################################### 100.0%
==> Fetching jenkins
==> Downloading https://ghcr.io/v2/homebrew/core/jenkins/blobs/sha256:0d962b21c4f6e170218bb7e0763a31e73540858034bb2d87f1dcb0f0f406e93e
##################################################################################################################################### 100.0%
==> Downloading https://ghcr.io/v2/homebrew/core/docker-compose/manifests/2.33.1
##################################################################################################################################### 100.0%
==> Fetching docker-compose
==> Downloading https://ghcr.io/v2/homebrew/core/docker-compose/blobs/sha256:0c2e2927c3591a33ec152ca4efa8c589c445c66680caaed4270c076f0d4b061
##################################################################################################################################### 100.0%
==> Downloading https://ghcr.io/v2/homebrew/core/openshift-cli/manifests/4.17.16
##################################################################################################################################### 100.0%
==> Fetching openshift-cli
==> Downloading https://ghcr.io/v2/homebrew/core/openshift-cli/blobs/sha256:329fd332f83bc946fc87e1b8710074c551e79fa7a97e4480b87f2143683ecefc
##################################################################################################################################### 100.0%
==> Downloading https://ghcr.io/v2/homebrew/core/fzf/manifests/0.60.2
##################################################################################################################################### 100.0%
==> Fetching fzf
==> Downloading https://ghcr.io/v2/homebrew/core/fzf/blobs/sha256:659ef1f6197f2f1f584f524218e90f4bdecd7f8b38d67a3425e992f180ea8a47
##################################################################################################################################### 100.0%
==> Upgrading sqlite
  3.49.0 -> 3.49.1 
==> Pouring sqlite--3.49.1.arm64_sequoia.bottle.tar.gz
🍺  /opt/homebrew/Cellar/sqlite/3.49.1: 13 files, 4.7MB
==> Running `brew cleanup sqlite`...
Disable this behaviour by setting HOMEBREW_NO_INSTALL_CLEANUP.
Hide these hints with HOMEBREW_NO_ENV_HINTS (see `man brew`).
Removing: /opt/homebrew/Cellar/sqlite/3.49.0... (13 files, 4.7MB)
Removing: /Users/henry/Library/Caches/Homebrew/sqlite_bottle_manifest--3.49.0... (9.5KB)
Removing: /Users/henry/Library/Caches/Homebrew/sqlite--3.49.0... (2.2MB)
==> Upgrading hwloc
  2.11.2 -> 2.12.0 
==> Pouring hwloc--2.12.0.arm64_sequoia.bottle.tar.gz
🍺  /opt/homebrew/Cellar/hwloc/2.12.0: 976 files, 10.7MB
==> Running `brew cleanup hwloc`...
Removing: /opt/homebrew/Cellar/hwloc/2.11.2... (972 files, 10.6MB)
==> Upgrading tree-sitter
  0.24.7 -> 0.25.2 
==> Pouring tree-sitter--0.25.2.arm64_sequoia.bottle.tar.gz
🍺  /opt/homebrew/Cellar/tree-sitter/0.25.2: 14 files, 8.8MB
==> Running `brew cleanup tree-sitter`...
Removing: /opt/homebrew/Cellar/tree-sitter/0.24.7... (15 files, 15MB)
Removing: /Users/henry/Library/Caches/Homebrew/tree-sitter_bottle_manifest--0.24.7... (7.4KB)
Removing: /Users/henry/Library/Caches/Homebrew/tree-sitter--0.24.7... (5.5MB)
==> Upgrading docker-completion
  27.5.1 -> 28.0.0 
==> Pouring docker-completion--28.0.0.all.bottle.tar.gz
🍺  /opt/homebrew/Cellar/docker-completion/28.0.0: 10 files, 341.8KB
==> Running `brew cleanup docker-completion`...
Removing: /opt/homebrew/Cellar/docker-completion/27.5.1... (10 files, 342KB)
Removing: /Users/henry/Library/Caches/Homebrew/docker-completion_bottle_manifest--27.5.1... (1.9KB)
Removing: /Users/henry/Library/Caches/Homebrew/docker-completion--27.5.1... (69.2KB)
==> Upgrading docker
  27.5.1 -> 28.0.0 
==> Pouring docker--28.0.0.arm64_sequoia.bottle.tar.gz
🍺  /opt/homebrew/Cellar/docker/28.0.0: 13 files, 26.7MB
==> Running `brew cleanup docker`...
Removing: /opt/homebrew/Cellar/docker/27.5.1... (14 files, 26.2MB)
Removing: /Users/henry/Library/Caches/Homebrew/docker_bottle_manifest--27.5.1... (8KB)
Removing: /Users/henry/Library/Caches/Homebrew/docker--27.5.1... (8.6MB)
==> Upgrading libpng
  1.6.46 -> 1.6.47 
==> Pouring libpng--1.6.47.arm64_sequoia.bottle.tar.gz
🍺  /opt/homebrew/Cellar/libpng/1.6.47: 28 files, 1.3MB
==> Running `brew cleanup libpng`...
Removing: /opt/homebrew/Cellar/libpng/1.6.46... (28 files, 1.4MB)
Removing: /Users/henry/Library/Caches/Homebrew/libpng_bottle_manifest--1.6.46... (8.1KB)
Removing: /Users/henry/Library/Caches/Homebrew/libpng--1.6.46... (456.3KB)
==> Upgrading harfbuzz
  10.2.0 -> 10.3.0 
==> Pouring harfbuzz--10.3.0.arm64_sequoia.bottle.tar.gz
🍺  /opt/homebrew/Cellar/harfbuzz/10.3.0: 77 files, 9.8MB
==> Running `brew cleanup harfbuzz`...
Removing: /opt/homebrew/Cellar/harfbuzz/10.2.0... (77 files, 9.8MB)
Removing: /Users/henry/Library/Caches/Homebrew/harfbuzz_bottle_manifest--10.2.0... (28.7KB)
Removing: /Users/henry/Library/Caches/Homebrew/harfbuzz--10.2.0... (2.5MB)
==> Upgrading openssh
  9.9p1 -> 9.9p2 
==> Pouring openssh--9.9p2.arm64_sequoia.bottle.tar.gz
🍺  /opt/homebrew/Cellar/openssh/9.9p2: 47 files, 6.7MB
==> Running `brew cleanup openssh`...
Removing: /opt/homebrew/Cellar/openssh/9.9p1... (47 files, 6.8MB)
==> Upgrading libassuan
  3.0.1 -> 3.0.2 
==> Pouring libassuan--3.0.2.arm64_sequoia.bottle.tar.gz
🍺  /opt/homebrew/Cellar/libassuan/3.0.2: 18 files, 566.8KB
==> Running `brew cleanup libassuan`...
Removing: /opt/homebrew/Cellar/libassuan/3.0.1... (18 files, 559.5KB)
==> Upgrading emacs
  29.4_1 -> 29.4_2 
==> Pouring emacs--29.4_2.arm64_sequoia.bottle.tar.gz
🍺  /opt/homebrew/Cellar/emacs/29.4_2: 4,227 files, 119.2MB
==> Running `brew cleanup emacs`...
Removing: /opt/homebrew/Cellar/emacs/29.4_1... (4,227 files, 119.2MB)
==> Upgrading snort
  3.6.3.0 -> 3.7.0.0 
==> Pouring snort--3.7.0.0.arm64_sequoia.bottle.tar.gz
==> Caveats
For snort to be functional, you need to update the permissions for /dev/bpf*
so that they can be read by non-root users.  This can be done manually using:
    sudo chmod o+r /dev/bpf*
or you could create a startup item to do this for you.
==> Summary
🍺  /opt/homebrew/Cellar/snort/3.7.0.0: 326 files, 12.0MB
==> Running `brew cleanup snort`...
Removing: /opt/homebrew/Cellar/snort/3.6.3.0... (325 files, 11.9MB)
Removing: /Users/henry/Library/Caches/Homebrew/snort_bottle_manifest--3.6.3.0... (16.5KB)
Removing: /Users/henry/Library/Caches/Homebrew/snort--3.6.3.0... (2.8MB)
==> Upgrading zstd
  1.5.6 -> 1.5.7 
==> Pouring zstd--1.5.7.arm64_sequoia.bottle.tar.gz
🍺  /opt/homebrew/Cellar/zstd/1.5.7: 32 files, 2.2MB
==> Running `brew cleanup zstd`...
Removing: /opt/homebrew/Cellar/zstd/1.5.6... (31 files, 2.2MB)
==> Upgrading socat
  1.8.0.2 -> 1.8.0.3 
==> Pouring socat--1.8.0.3.arm64_sequoia.bottle.tar.gz
🍺  /opt/homebrew/Cellar/socat/1.8.0.3: 16 files, 970.9KB
==> Running `brew cleanup socat`...
Removing: /opt/homebrew/Cellar/socat/1.8.0.2... (16 files, 962.3KB)
==> Upgrading jenkins
  2.497 -> 2.498 
==> Pouring jenkins--2.498.all.bottle.tar.gz
==> Caveats
Note: When using launchctl the port will be 8080.

To start jenkins now and restart at login:
  brew services start jenkins
Or, if you don't want/need a background service you can just run:
  /opt/homebrew/opt/jenkins/bin/jenkins --httpListenAddress\=127.0.0.1 --httpPort\=8080
==> Summary
🍺  /opt/homebrew/Cellar/jenkins/2.498: 9 files, 93.8MB
==> Running `brew cleanup jenkins`...
Removing: /opt/homebrew/Cellar/jenkins/2.497... (9 files, 93.9MB)
Removing: /Users/henry/Library/Caches/Homebrew/jenkins_bottle_manifest--2.497... (6.2KB)
Removing: /Users/henry/Library/Caches/Homebrew/jenkins--2.497... (93.3MB)
==> Upgrading docker-compose
  2.33.0 -> 2.33.1 
==> Pouring docker-compose--2.33.1.arm64_sequoia.bottle.tar.gz
==> Caveats
Compose is a Docker plugin. For Docker to find the plugin, add "cliPluginsExtraDirs" to ~/.docker/config.json:
  "cliPluginsExtraDirs": [
      "/opt/homebrew/lib/docker/cli-plugins"
  ]
==> Summary
🍺  /opt/homebrew/Cellar/docker-compose/2.33.1: 8 files, 60MB
==> Running `brew cleanup docker-compose`...
Removing: /opt/homebrew/Cellar/docker-compose/2.33.0... (8 files, 60.2MB)
Removing: /Users/henry/Library/Caches/Homebrew/docker-compose_bottle_manifest--2.33.0... (7.3KB)
Removing: /Users/henry/Library/Caches/Homebrew/docker-compose--2.33.0... (17.3MB)
==> Upgrading openshift-cli
  4.17.15 -> 4.17.16 
==> Pouring openshift-cli--4.17.16.arm64_sequoia.bottle.tar.gz
==> Caveats
zsh completions have been installed to:
  /opt/homebrew/share/zsh/site-functions
==> Summary
🍺  /opt/homebrew/Cellar/openshift-cli/4.17.16: 9 files, 134.4MB
==> Running `brew cleanup openshift-cli`...
Removing: /opt/homebrew/Cellar/openshift-cli/4.17.15... (9 files, 134.3MB)
Removing: /Users/henry/Library/Caches/Homebrew/openshift-cli_bottle_manifest--4.17.15... (7.8KB)
Removing: /Users/henry/Library/Caches/Homebrew/openshift-cli--4.17.15... (55.5MB)
==> Upgrading fzf
  0.60.0 -> 0.60.2 
==> Pouring fzf--0.60.2.arm64_sequoia.bottle.tar.gz
==> Caveats
To set up shell integration, see:
  https://github.com/junegunn/fzf#setting-up-shell-integration
To use fzf in Vim, add the following line to your .vimrc:
  set rtp+=/opt/homebrew/opt/fzf
==> Summary
🍺  /opt/homebrew/Cellar/fzf/0.60.2: 19 files, 4.4MB
==> Running `brew cleanup fzf`...
Removing: /opt/homebrew/Cellar/fzf/0.60.0... (19 files, 4.4MB)
Removing: /Users/henry/Library/Caches/Homebrew/fzf_bottle_manifest--0.60.0... (7.4KB)
Removing: /Users/henry/Library/Caches/Homebrew/fzf--0.60.0... (1.7MB)
==> Caveats
==> snort
For snort to be functional, you need to update the permissions for /dev/bpf*
so that they can be read by non-root users.  This can be done manually using:
    sudo chmod o+r /dev/bpf*
or you could create a startup item to do this for you.
==> jenkins
Note: When using launchctl the port will be 8080.

To start jenkins now and restart at login:
  brew services start jenkins
Or, if you don't want/need a background service you can just run:
  /opt/homebrew/opt/jenkins/bin/jenkins --httpListenAddress\=127.0.0.1 --httpPort\=8080
==> docker-compose
Compose is a Docker plugin. For Docker to find the plugin, add "cliPluginsExtraDirs" to ~/.docker/config.json:
  "cliPluginsExtraDirs": [
      "/opt/homebrew/lib/docker/cli-plugins"
  ]
==> openshift-cli
zsh completions have been installed to:
  /opt/homebrew/share/zsh/site-functions
==> fzf
To set up shell integration, see:
  https://github.com/junegunn/fzf#setting-up-shell-integration
To use fzf in Vim, add the following line to your .vimrc:
  set rtp+=/opt/homebrew/opt/fzf

    ~ ······························································································· took 34s   at 02:59:14 PM       ~ ······························································································· took 34s   at 02:59:14     ~ ··    ~ ································································································· took 34s   at    ~ ········    ~ ································································································· t    ~ ······················    ~ ····························································································    ~ ········································    ~ ··········································································    ~ ························································································· took 34s   at 02:59:14 PM  ─╮
❯ ssh henry@192.168.1.105                                                                                                          ─╯
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
Someone could be eavesdropping on you right now (man-in-the-middle attack)!
It is also possible that a host key has just been changed.
The fingerprint for the ED25519 key sent by the remote host is
SHA256:y53O50hSnq/g0bVeuft/1ctMUCrQuevLN2M9yGX3HKI.
Please contact your system administrator.
Add correct host key in /Users/henry/.ssh/known_hosts to get rid of this message.
Offending ECDSA key in /Users/henry/.ssh/known_hosts:9
Host key for 192.168.1.105 has changed and you have requested strict checking.
Host key verification failed.

    ~ ······························································································ 255 ✘  at 09:46:36 PM  ─╮
❯ vim ~/Users/henry.ssh/known_hosts                                                                                                ─╯

    ~ ························································································· took 23s   at 09:47:21 PM  ─╮
❯ ls                                                                                                                               ─╯
Applications  LFS258_V2024-03-14_SOLUTIONS.tar.xz  Public                            hr-vault-main-pa
Desktop       Library                              Sites                             kali-shelz
Documents     Movies                               git-runner-example.yml            packages.txt
Downloads     Music                                git-scriptrunner-outline-yaml.sh  suid-containerescape-example.sh
Github        Oracle                               go                                tmp
LFS258        Pictures                             go-shelz                          vault-main

    ~ ······································································································ at 09:47:23 PM  ─╮
❯ ls -alt                                                                                                                          ─╯
total 544
drwxr-xr-x+  65 henry staff   2080 Feb 25 21:47  .
-rw-------    1 henry staff  40272 Feb 25 21:47  .zsh_history
drwxr-xr-x    2 henry staff     64 Feb 25 21:47  tmp
-rw-------    1 henry staff  36322 Feb 25 21:47  .viminfo
drwxr-xr-x   10 henry staff    320 Feb 25 21:46  .cache
drwxr-xr-x   21 henry staff    672 Feb 25 15:21  hr-vault-main-pa
drwx------    9 henry staff    288 Feb 17 21:19  .Trash
drwx------   60 henry staff   1920 Feb 17 21:19  Downloads
drwx------   19 henry staff    608 Feb 17 21:17  .zsh_sessions
drwx------   27 henry staff    864 Feb 17 17:49  Desktop
drwxr-xr-x    3 henry staff     96 Feb 17 02:42  .kube
-r--r--r--    1 henry staff 119752 Feb 17 01:57 '.zcompdump-MacBook Pro-5.9.zwc'
-rw-r--r--    1 henry staff  52872 Feb 17 01:57 '.zcompdump-MacBook Pro-5.9'
-rw-r--r--    1 henry staff    417 Feb 16 17:40  .vimrc
-rw-r--r--    1 henry staff   7691 Feb 16 09:11  .zshrc
drwxr-x---    3 henry staff     96 Feb 15 20:08  .vim
-rw-r--r--    1 henry staff  95437 Feb 15 19:56  .p10k.zsh
drwxr-xr-x   24 henry staff    768 Feb 15 19:52  .oh-my-zsh
drwxr-xr-x    7 root  admin    224 Feb 14 12:58  ..
drwxr-xr-x   12 henry staff    384 Feb 14 12:55  .docker
drwxr-xr-x   11 henry staff    352 Feb  7 18:36  .anydesk
drwx------    6 henry staff    192 Feb  7 18:36  Movies
drwxrwxr-x    7 henry admin    224 Feb  7 17:50  Applications
-rw-r--r--    1 henry staff  18436 Feb  6 20:51  .DS_Store
drwx------   24 henry staff    768 Feb  6 15:03  Documents
drwxr-xr-x    9 henry staff    288 Feb  6 00:02  kali-shelz
drwx------  110 henry staff   3520 Feb  5 23:37  Library
drwx------    8 henry staff    256 Feb  5 22:18  .tor
drwx------    6 henry staff    192 Feb  1 16:51  .ssh
drwxr-xr-x    4 henry staff    128 Feb  1 14:39  LFS258
drwxr-xr-x    7 henry staff    224 Jan 26 13:18  .local
-rw-r--r--    1 henry staff    180 Jan 26 11:46  .wget-hsts
-rw-r--r--    1 henry staff      0 Jan 26 11:46  .dircolors-gruvbox
-rw-r--r--    1 henry staff  26996 Jan 24 22:16  LFS258_V2024-03-14_SOLUTIONS.tar.xz
drwx------   24 henry staff    768 Jan 13 22:11  Pictures
drwxr-xr-x    3 henry staff     96 Dec 30 18:34  Sites
drwx------    4 henry staff    128 Dec 24 22:47  .vnc
-rw-r--r--    1 henry staff  52155 Dec 24 19:27 '.zcompdump-Henry’s Laptop-5.9'
drwxr-xr-x    5 henry staff    160 Dec 17 18:11  .jupyter
drwxr-xr-x    2 henry staff     64 Dec 17 18:09  .ipython
-rw-r--r--    1 henry staff   1571 Nov 17 10:07  git-scriptrunner-outline-yaml.sh
-rw-r--r--    1 henry staff   2235 Nov 17 10:06  suid-containerescape-example.sh
-rw-r--r--    1 henry staff   1423 Nov 17 10:06  git-runner-example.yml
-rw-r--r--    1 henry staff   1389 Nov 17 09:27  packages.txt
drwxr-x--x    8 henry staff    256 Nov 17 03:24  .config
-rw-r--r--    1 henry staff    183 Oct 30 21:04  .gitconfig
drwxr-xr-x    7 henry staff    224 Oct 30 21:03  Github
drwxr-xr-x    3 henry staff     96 Oct 28 18:27  Oracle
drwxr-xr-x    3 henry staff     96 Sep  1 09:30  go
drwxr-xr-x    3 henry staff     96 Jun 28  2024  .BrowserLock
drwxr-xr-x    3 henry staff     96 Jun 17  2024  go-shelz
drwx------    8 henry staff    256 Jun  8  2024  vault-main
drwxr-xr-x    3 henry staff     96 Apr 13  2024  .bridgecrew
drwxr-xr-x    5 henry staff    160 Mar 25  2024  .npm
drwxr-xr-x    4 henry staff    128 Feb 25  2024  .bridge
drwxr-xr-x   10 henry staff    320 Jan 20  2024  .minikube
drwxr-xr-x    6 henry staff    192 Dec 29  2023  .rest-client
-rw-r--r--    1 henry staff  54489 Dec 24  2023  .zcompdump
drwxr-xr-x    3 henry staff     96 Dec 24  2023  .vs-kubernetes
drwxr-xr-x    3 henry staff     96 Dec 24  2023  .redhat
drwxr-xr-x    5 henry staff    160 Dec 24  2023  .vscode
-rw-r--r--    1 henry staff     43 Dec 24  2023  .zprofile
drwx------    4 henry staff    128 Dec 24  2023  Music
-r--------    1 henry staff      7 Dec 24  2023  .CFUserTextEncoding
drwxr-xr-x    4 henry staff    128 Dec 24  2023  Public

    ~ ······································································································ at 09:47:27 PM  ─╮
❯ vim .ssh/known_hosts                                                                                                             ─╯

    ~ ························································································· took 25s   at 09:48:00 PM  ─╮
❯ ssh henry@192.168.1.105                                                                                                          ─╯
The authenticity of host '192.168.1.105 (192.168.1.105)' can't be established.
ED25519 key fingerprint is SHA256:y53O50hSnq/g0bVeuft/1ctMUCrQuevLN2M9yGX3HKI.
This host key is known by the following other names/addresses:
    ~/.ssh/known_hosts:14: 192.168.1.100
    ~/.ssh/known_hosts:16: 192.168.1.106
    ~/.ssh/known_hosts:17: 192.168.1.104
    ~/.ssh/known_hosts:20: 192.168.1.116
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added '192.168.1.105' (ED25519) to the list of known hosts.
henry@192.168.1.105's password: 
Permission denied, please try again.
henry@192.168.1.105's password: 
Welcome to Ubuntu 22.04.5 LTS (GNU/Linux 5.15.0-131-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/pro

 System information as of Wed Feb 26 02:48:35 AM UTC 2025

  System load:  0.0                Temperature:           39.0 C
  Usage of /:   19.0% of 97.87GB   Processes:             583
  Memory usage: 0%                 Users logged in:       0
  Swap usage:   0%                 IPv4 address for eno3: 192.168.1.105

 * Strictly confined Kubernetes makes edge and IoT secure. Learn how MicroK8s
   just raised the bar for easy, resilient and secure K8s cluster deployment.

   https://ubuntu.com/engage/secure-kubernetes-at-the-edge

Expanded Security Maintenance for Applications is not enabled.

3 updates can be applied immediately.
To see these additional updates run: apt list --upgradable

9 additional security updates can be applied with ESM Apps.
Learn more about enabling ESM Apps service at https://ubuntu.com/esm


*** System restart required ***
Last login: Mon Feb 17 08:08:27 2025 from 192.168.1.102
henry@cp:~$ ps -aux 
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  0.0  0.0 167696 13096 ?        Rs   Feb17   8:26 /sbin/init
root           2  0.0  0.0      0     0 ?        S    Feb17   0:01 [kthreadd]
root           3  0.0  0.0      0     0 ?        I<   Feb17   0:00 [rcu_gp]
root           4  0.0  0.0      0     0 ?        I<   Feb17   0:00 [rcu_par_gp]
root           5  0.0  0.0      0     0 ?        I<   Feb17   0:00 [slub_flushwq]
root           6  0.0  0.0      0     0 ?        I<   Feb17   0:00 [netns]
root           8  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/0:0H-events_highpri]
root           9  0.0  0.0      0     0 ?        I    Feb17   0:07 [kworker/u112:0-ext4-rsv-conversion]
root          11  0.0  0.0      0     0 ?        I<   Feb17   0:00 [mm_percpu_wq]
root          12  0.0  0.0      0     0 ?        S    Feb17   0:00 [rcu_tasks_rude_]
root          13  0.0  0.0      0     0 ?        S    Feb17   0:00 [rcu_tasks_trace]
root          14  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/0]
root          15  0.0  0.0      0     0 ?        I    Feb17   0:30 [rcu_sched]
root          16  0.0  0.0      0     0 ?        S    Feb17   0:02 [migration/0]
root          17  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/0]
root          19  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/0]
root          20  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/1]
root          21  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/1]
root          22  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/1]
root          23  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/1]
root          25  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/1:0H-events_highpri]
root          27  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/2]
root          28  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/2]
root          29  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/2]
root          30  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/2]
root          32  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/2:0H-events_highpri]
root          33  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/3]
root          34  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/3]
root          35  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/3]
root          36  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/3]
root          38  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/3:0H-kblockd]
root          39  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/4]
root          40  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/4]
root          41  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/4]
root          42  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/4]
root          44  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/4:0H-kblockd]
root          45  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/5]
root          46  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/5]
root          47  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/5]
root          48  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/5]
root          50  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/5:0H-kblockd]
root          51  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/6]
root          52  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/6]
root          53  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/6]
root          54  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/6]
root          56  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/6:0H-kblockd]
root          57  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/7]
root          58  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/7]
root          59  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/7]
root          60  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/7]
root          62  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/7:0H-kblockd]
root          63  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/8]
root          64  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/8]
root          65  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/8]
root          66  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/8]
root          68  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/8:0H-kblockd]
root          69  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/9]
root          70  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/9]
root          71  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/9]
root          72  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/9]
root          74  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/9:0H-kblockd]
root          75  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/10]
root          76  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/10]
root          77  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/10]
root          78  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/10]
root          80  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/10:0H-kblockd]
root          81  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/11]
root          82  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/11]
root          83  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/11]
root          84  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/11]
root          86  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/11:0H-kblockd]
root          87  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/12]
root          88  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/12]
root          89  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/12]
root          90  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/12]
root          92  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/12:0H-events_highpri]
root          93  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/13]
root          94  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/13]
root          95  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/13]
root          96  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/13]
root          98  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/13:0H-events_highpri]
root          99  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/14]
root         100  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/14]
root         101  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/14]
root         102  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/14]
root         104  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/14:0H-events_highpri]
root         105  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/15]
root         106  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/15]
root         107  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/15]
root         108  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/15]
root         110  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/15:0H-kblockd]
root         111  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/16]
root         112  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/16]
root         113  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/16]
root         114  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/16]
root         116  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/16:0H-events_highpri]
root         117  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/17]
root         118  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/17]
root         119  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/17]
root         120  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/17]
root         122  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/17:0H-kblockd]
root         123  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/18]
root         124  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/18]
root         125  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/18]
root         126  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/18]
root         128  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/18:0H-kblockd]
root         129  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/19]
root         130  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/19]
root         131  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/19]
root         132  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/19]
root         134  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/19:0H-kblockd]
root         135  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/20]
root         136  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/20]
root         137  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/20]
root         138  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/20]
root         140  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/20:0H-events_highpri]
root         141  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/21]
root         142  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/21]
root         143  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/21]
root         144  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/21]
root         146  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/21:0H-events_highpri]
root         147  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/22]
root         148  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/22]
root         149  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/22]
root         150  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/22]
root         152  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/22:0H-kblockd]
root         153  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/23]
root         154  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/23]
root         155  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/23]
root         156  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/23]
root         158  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/23:0H-events_highpri]
root         159  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/24]
root         160  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/24]
root         161  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/24]
root         162  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/24]
root         164  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/24:0H-events_highpri]
root         165  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/25]
root         166  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/25]
root         167  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/25]
root         168  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/25]
root         170  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/25:0H-events_highpri]
root         171  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/26]
root         172  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/26]
root         173  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/26]
root         174  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/26]
root         176  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/26:0H-events_highpri]
root         177  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/27]
root         178  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/27]
root         179  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/27]
root         180  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/27]
root         182  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/27:0H-events_highpri]
root         183  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/28]
root         184  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/28]
root         185  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/28]
root         186  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/28]
root         188  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/28:0H-events_highpri]
root         189  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/29]
root         190  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/29]
root         191  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/29]
root         192  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/29]
root         194  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/29:0H-kblockd]
root         195  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/30]
root         196  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/30]
root         197  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/30]
root         198  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/30]
root         200  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/30:0H-kblockd]
root         201  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/31]
root         202  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/31]
root         203  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/31]
root         204  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/31]
root         206  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/31:0H-kblockd]
root         207  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/32]
root         208  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/32]
root         209  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/32]
root         210  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/32]
root         212  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/32:0H-kblockd]
root         213  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/33]
root         214  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/33]
root         215  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/33]
root         216  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/33]
root         218  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/33:0H-events_highpri]
root         219  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/34]
root         220  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/34]
root         221  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/34]
root         222  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/34]
root         224  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/34:0H-events_highpri]
root         225  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/35]
root         226  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/35]
root         227  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/35]
root         228  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/35]
root         230  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/35:0H-kblockd]
root         231  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/36]
root         232  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/36]
root         233  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/36]
root         234  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/36]
root         236  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/36:0H-events_highpri]
root         237  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/37]
root         238  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/37]
root         239  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/37]
root         240  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/37]
root         242  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/37:0H-kblockd]
root         243  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/38]
root         244  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/38]
root         245  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/38]
root         246  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/38]
root         248  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/38:0H-events_highpri]
root         249  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/39]
root         250  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/39]
root         251  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/39]
root         252  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/39]
root         254  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/39:0H-events_highpri]
root         255  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/40]
root         256  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/40]
root         257  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/40]
root         258  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/40]
root         260  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/40:0H-kblockd]
root         261  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/41]
root         262  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/41]
root         263  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/41]
root         264  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/41]
root         266  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/41:0H-events_highpri]
root         267  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/42]
root         268  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/42]
root         269  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/42]
root         270  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/42]
root         272  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/42:0H-kblockd]
root         273  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/43]
root         274  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/43]
root         275  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/43]
root         276  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/43]
root         278  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/43:0H-kblockd]
root         279  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/44]
root         280  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/44]
root         281  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/44]
root         282  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/44]
root         284  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/44:0H-events_highpri]
root         285  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/45]
root         286  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/45]
root         287  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/45]
root         288  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/45]
root         290  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/45:0H-events_highpri]
root         291  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/46]
root         292  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/46]
root         293  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/46]
root         294  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/46]
root         296  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/46:0H-kblockd]
root         297  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/47]
root         298  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/47]
root         299  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/47]
root         300  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/47]
root         302  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/47:0H-events_highpri]
root         303  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/48]
root         304  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/48]
root         305  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/48]
root         306  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/48]
root         308  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/48:0H-events_highpri]
root         309  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/49]
root         310  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/49]
root         311  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/49]
root         312  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/49]
root         314  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/49:0H-kblockd]
root         315  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/50]
root         316  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/50]
root         317  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/50]
root         318  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/50]
root         320  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/50:0H-kblockd]
root         321  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/51]
root         322  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/51]
root         323  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/51]
root         324  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/51]
root         326  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/51:0H-events_highpri]
root         327  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/52]
root         328  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/52]
root         329  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/52]
root         330  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/52]
root         332  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/52:0H-events_highpri]
root         333  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/53]
root         334  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/53]
root         335  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/53]
root         336  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/53]
root         338  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/53:0H-events_highpri]
root         339  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/54]
root         340  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/54]
root         341  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/54]
root         342  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/54]
root         344  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/54:0H-kblockd]
root         345  0.0  0.0      0     0 ?        S    Feb17   0:00 [cpuhp/55]
root         346  0.0  0.0      0     0 ?        S    Feb17   0:00 [idle_inject/55]
root         347  0.0  0.0      0     0 ?        S    Feb17   0:03 [migration/55]
root         348  0.0  0.0      0     0 ?        S    Feb17   0:00 [ksoftirqd/55]
root         350  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/55:0H-kblockd]
root         351  0.0  0.0      0     0 ?        S    Feb17   0:00 [kdevtmpfs]
root         352  0.0  0.0      0     0 ?        I<   Feb17   0:00 [inet_frag_wq]
root         353  0.0  0.0      0     0 ?        S    Feb17   0:00 [kauditd]
root         355  0.0  0.0      0     0 ?        S    Feb17   0:00 [khungtaskd]
root         356  0.0  0.0      0     0 ?        S    Feb17   0:00 [oom_reaper]
root         357  0.0  0.0      0     0 ?        I<   Feb17   0:00 [writeback]
root         358  0.0  0.0      0     0 ?        S    Feb17   0:20 [kcompactd0]
root         359  0.0  0.0      0     0 ?        S    Feb17   0:21 [kcompactd1]
root         360  0.0  0.0      0     0 ?        SN   Feb17   0:00 [ksmd]
root         361  0.0  0.0      0     0 ?        SN   Feb17   0:00 [khugepaged]
root         408  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kintegrityd]
root         409  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kblockd]
root         410  0.0  0.0      0     0 ?        I<   Feb17   0:00 [blkcg_punt_bio]
root         411  0.0  0.0      0     0 ?        I<   Feb17   0:00 [tpm_dev_wq]
root         412  0.0  0.0      0     0 ?        I<   Feb17   0:00 [ata_sff]
root         413  0.0  0.0      0     0 ?        I<   Feb17   0:00 [md]
root         414  0.0  0.0      0     0 ?        I<   Feb17   0:00 [edac-poller]
root         415  0.0  0.0      0     0 ?        I<   Feb17   0:00 [devfreq_wq]
root         416  0.0  0.0      0     0 ?        S    Feb17   0:00 [watchdogd]
root         419  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/0:1H-kblockd]
root         421  0.0  0.0      0     0 ?        S    Feb17   0:00 [kswapd0]
root         422  0.0  0.0      0     0 ?        S    Feb17   0:00 [kswapd1]
root         423  0.0  0.0      0     0 ?        S    Feb17   0:00 [ecryptfs-kthrea]
root         426  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kthrotld]
root         427  0.0  0.0      0     0 ?        S    Feb17   0:00 [irq/25-aerdrv]
root         428  0.0  0.0      0     0 ?        S    Feb17   0:00 [irq/26-aerdrv]
root         429  0.0  0.0      0     0 ?        S    Feb17   0:00 [irq/27-aerdrv]
root         430  0.0  0.0      0     0 ?        S    Feb17   0:00 [irq/28-aerdrv]
root         431  0.0  0.0      0     0 ?        S    Feb17   0:00 [irq/29-aerdrv]
root         432  0.0  0.0      0     0 ?        S    Feb17   0:00 [irq/31-aerdrv]
root         434  0.0  0.0      0     0 ?        S    Feb17   0:00 [irq/35-aerdrv]
root         436  0.0  0.0      0     0 ?        S    Feb17   0:00 [irq/36-aerdrv]
root         437  0.0  0.0      0     0 ?        I<   Feb17   0:00 [acpi_thermal_pm]
root         439  0.0  0.0      0     0 ?        I    Feb17   0:10 [kworker/28:2-mm_percpu_wq]
root         440  0.0  0.0      0     0 ?        I<   Feb17   0:00 [vfio-irqfd-clea]
root         444  0.0  0.0      0     0 ?        I    Feb17   0:07 [kworker/u112:1-poll_megasas0_status]
root         445  0.0  0.0      0     0 ?        I<   Feb17   0:00 [mld]
root         446  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/28:1H-kblockd]
root         447  0.0  0.0      0     0 ?        I<   Feb17   0:00 [ipv6_addrconf]
root         461  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kstrp]
root         489  0.0  0.0      0     0 ?        I    Feb17   0:05 [kworker/16:1-events]
root         491  0.0  0.0      0     0 ?        I    Feb17   0:05 [kworker/22:1-mm_percpu_wq]
root         492  0.0  0.0      0     0 ?        I    Feb17   0:04 [kworker/26:1-mm_percpu_wq]
root         494  0.0  0.0      0     0 ?        I    Feb17   0:03 [kworker/32:1-mm_percpu_wq]
root         499  0.0  0.0      0     0 ?        I    Feb17   0:04 [kworker/50:1-events]
root         500  0.0  0.0      0     0 ?        I    Feb17   0:03 [kworker/52:1-mm_percpu_wq]
root         504  0.0  0.0      0     0 ?        I<   Feb17   0:00 [zswap-shrink]
root         531  0.0  0.0      0     0 ?        I    Feb17   0:04 [kworker/24:2-events]
root         566  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/u115:0]
root         567  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/u116:0]
root         568  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/u117:0]
root         575  0.0  0.0      0     0 ?        I<   Feb17   0:00 [charger_manager]
root         598  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/14:1H-kblockd]
root         621  0.0  0.0      0     0 ?        I<   Feb17   0:01 [kworker/1:1H-kblockd]
root         624  0.0  0.0      0     0 ?        S    Feb17   0:00 [scsi_eh_0]
root         625  0.0  0.0      0     0 ?        I<   Feb17   0:00 [scsi_tmf_0]
root         629  0.0  0.0      0     0 ?        I<   Feb17   0:00 [cryptd]
root         681  0.0  0.0      0     0 ?        S    Feb17   0:00 [scsi_eh_1]
root         683  0.0  0.0      0     0 ?        I<   Feb17   0:00 [scsi_tmf_1]
root         692  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/2:1H-kblockd]
root         703  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/47:1H-kblockd]
root         704  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/39:1H-kblockd]
root         705  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/25:1H-kblockd]
root         707  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/20:1H-kblockd]
root         708  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/26:1H-kblockd]
root         709  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/51:1H-kblockd]
root         711  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/44:1H-kblockd]
root         713  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/16:1H-kblockd]
root         730  0.0  0.0      0     0 ?        S    Feb17   0:00 [scsi_eh_2]
root         731  0.0  0.0      0     0 ?        I<   Feb17   0:00 [scsi_tmf_2]
root         732  0.0  0.0      0     0 ?        S    Feb17   0:00 [scsi_eh_3]
root         733  0.0  0.0      0     0 ?        I<   Feb17   0:00 [scsi_tmf_3]
root         735  0.0  0.0      0     0 ?        S    Feb17   0:00 [scsi_eh_4]
root         736  0.0  0.0      0     0 ?        I<   Feb17   0:00 [scsi_tmf_4]
root         751  0.0  0.0      0     0 ?        I<   Feb17   0:00 [poll_megasas0_s]
root         754  0.0  0.0      0     0 ?        S    Feb17   0:00 [scsi_eh_5]
root         755  0.0  0.0      0     0 ?        I<   Feb17   0:00 [scsi_tmf_5]
root         756  0.0  0.0      0     0 ?        S    Feb17   0:00 [scsi_eh_6]
root         757  0.0  0.0      0     0 ?        I<   Feb17   0:00 [scsi_tmf_6]
root         758  0.0  0.0      0     0 ?        S    Feb17   0:00 [scsi_eh_7]
root         759  0.0  0.0      0     0 ?        I<   Feb17   0:00 [scsi_tmf_7]
root         760  0.0  0.0      0     0 ?        S    Feb17   0:00 [scsi_eh_8]
root         761  0.0  0.0      0     0 ?        I<   Feb17   0:00 [scsi_tmf_8]
root         762  0.0  0.0      0     0 ?        S    Feb17   0:00 [scsi_eh_9]
root         763  0.0  0.0      0     0 ?        I<   Feb17   0:00 [scsi_tmf_9]
root         764  0.0  0.0      0     0 ?        S    Feb17   0:00 [scsi_eh_10]
root         765  0.0  0.0      0     0 ?        I<   Feb17   0:00 [scsi_tmf_10]
root         772  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/54:1H-kblockd]
root         790  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/45:1H-kblockd]
root         794  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/33:1H-kblockd]
root         795  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/52:1H-kblockd]
root         797  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kdmflush]
root         799  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/53:1H-kblockd]
root         801  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/34:1H-kblockd]
root         825  0.0  0.0      0     0 ?        I<   Feb17   0:00 [raid5wq]
root         873  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/32:1H-kblockd]
root         874  0.0  0.0      0     0 ?        S    Feb17   0:17 [jbd2/dm-0-8]
root         875  0.0  0.0      0     0 ?        I<   Feb17   0:00 [ext4-rsv-conver]
root         898  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/24:1H-kblockd]
root         907  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/13:1H-kblockd]
root         910  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/22:1H-kblockd]
root         914  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/42:1H-kblockd]
root         916  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/40:1H-kblockd]
root         918  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/4:1H-kblockd]
root         921  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/6:1H-kblockd]
root         926  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/8:1H-kblockd]
root         941  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/11:1H-kblockd]
root         943  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/30:1H-kblockd]
root         944  0.0  0.0      0     0 ?        I<   Feb17   0:01 [kworker/3:1H-kblockd]
root         945  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/7:1H-kblockd]
root         952  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/10:1H-kblockd]
root         953  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/46:1H-kblockd]
root         963  0.0  0.0 179044 119988 ?       S<s  Feb17   3:12 /lib/systemd/systemd-journald
root         980  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/9:1H-kblockd]
root         992  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kaluad]
root         995  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/18:1H-kblockd]
root         996  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kmpath_rdacd]
root         997  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kmpathd]
root         998  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kmpath_handlerd]
root        1000  0.0  0.0 289476 27256 ?        SLsl Feb17   0:44 /sbin/multipathd -d -s
root        1013  0.0  0.0  26276  7132 ?        Ss   Feb17   0:01 /lib/systemd/systemd-udevd
root        1093  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/17:1H-kblockd]
root        1094  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/19:1H-kblockd]
root        1095  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/29:1H-kblockd]
root        1096  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/50:1H-kblockd]
root        1097  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/35:1H-kblockd]
root        1098  0.0  0.0      0     0 ?        I<   Feb17   0:01 [kworker/5:1H-kblockd]
root        1099  0.0  0.0      0     0 ?        I<   Feb17   0:00 [ipmi-msghandler]
root        1101  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/49:1H-kblockd]
root        1110  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/48:1H-kblockd]
root        1119  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/43:1H-kblockd]
root        1135  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/38:1H-kblockd]
root        1140  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/23:1H-kblockd]
root        1168  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/27:1H-kblockd]
root        1178  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/41:1H-kblockd]
root        1193  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/36:1H-kblockd]
root        1195  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/12:1H-kblockd]
root        1198  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/21:1H-kblockd]
root        1200  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/37:1H-kblockd]
root        1253  0.0  0.0      0     0 ?        S    Feb17   0:00 [jbd2/sda2-8]
root        1254  0.0  0.0      0     0 ?        I<   Feb17   0:00 [ext4-rsv-conver]
systemd+    1288  0.0  0.0  89364  6600 ?        Ssl  Feb17   0:01 /lib/systemd/systemd-timesyncd
systemd+    1335  0.0  0.0  16260  7992 ?        Ss   Feb17   0:01 /lib/systemd/systemd-networkd
systemd+    1337  0.0  0.0  25804 13604 ?        Ss   Feb17   0:01 /lib/systemd/systemd-resolved
root        1346  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/15:1H-kblockd]
root        1352  0.0  0.0   6896  2928 ?        Ss   Feb17   0:01 /usr/sbin/cron -f -P
message+    1354  0.0  0.0   8996  5300 ?        Ss   Feb17   2:04 @dbus-daemon --system --address=systemd: --nofork --nopidfile --sys
root        1355  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/55:1H-kblockd]
root        1363  0.0  0.0  82928  4168 ?        Ssl  Feb17   3:33 /usr/sbin/irqbalance --foreground
root        1366  0.0  0.0  32820 19416 ?        Ss   Feb17   0:00 /usr/bin/python3 /usr/bin/networkd-dispatcher --run-startup-trigger
root        1367  0.0  0.0 234504  6848 ?        Ssl  Feb17   0:00 /usr/libexec/polkitd --no-debug
syslog      1368  0.0  0.0 222404  6328 ?        Ssl  Feb17   0:38 /usr/sbin/rsyslogd -n -iNONE
root        1374  0.0  0.0 3022524 35896 ?       Ssl  Feb17   1:44 /usr/lib/snapd/snapd
root        1379  0.0  0.0  16376  8696 ?        Ss   Feb17   0:42 /lib/systemd/systemd-logind
root        1382  0.0  0.0 392600 12952 ?        Ssl  Feb17   0:01 /usr/libexec/udisks2/udisksd
root        1383  0.1  0.0 4908788 50688 ?       Ssl  Feb17  16:06 /usr/bin/containerd
root        1400  0.0  0.0 244236 12132 ?        Ssl  Feb17   0:00 /usr/sbin/ModemManager
root        1410  0.0  0.0   6176  1124 tty1     Ss+  Feb17   0:00 /sbin/agetty -o -p -- \u --noclear tty1 linux
root        1431  0.0  0.0 109784 21680 ?        Ssl  Feb17   0:00 /usr/bin/python3 /usr/share/unattended-upgrades/unattended-upgrade-
root        1745  0.0  0.0      0     0 ?        I<   Feb17   0:00 [kworker/31:1H-kblockd]
root       46830  0.0  0.0 239612  8564 ?        Ssl  Feb17   0:00 /usr/libexec/upowerd
root       90061  0.0  0.0      0     0 ?        I    Feb17   0:07 [kworker/14:0-events]
root      189737  0.0  0.0 295592 20672 ?        Ssl  Feb18   0:02 /usr/libexec/packagekitd
root      327432  0.0  0.0  15436  9424 ?        Ss   Feb19   0:00 sshd: /usr/sbin/sshd -D [listener] 0 of 10-100 startups
root      368453  0.0  0.0      0     0 ?        I    Feb19   0:02 [kworker/54:1-mm_percpu_wq]
root      382498  0.0  0.0      0     0 ?        I    Feb19   0:05 [kworker/12:2-events]
root      387667  0.0  0.0      0     0 ?        I    Feb19   0:06 [kworker/8:0-events]
root      442204  0.0  0.0      0     0 ?        I    Feb19   0:06 [kworker/10:2-mm_percpu_wq]
root      456988  0.0  0.0      0     0 ?        I    Feb19   0:03 [kworker/25:1-mm_percpu_wq]
root      587635  0.0  0.0      0     0 ?        I    Feb20   0:02 [kworker/20:0-events]
root      603284  0.0  0.0      0     0 ?        I    Feb20   0:05 [kworker/6:1-mm_percpu_wq]
root      661916  0.0  0.0      0     0 ?        I    Feb21   0:02 [kworker/21:2-mm_percpu_wq]
root      662199  0.0  0.0      0     0 ?        I    Feb21   0:03 [kworker/40:2-mm_percpu_wq]
root      806371  0.0  0.0      0     0 ?        I    Feb22   0:01 [kworker/13:1-mm_percpu_wq]
root      842541  0.0  0.0      0     0 ?        I    Feb22   0:01 [kworker/43:2-mm_percpu_wq]
root      850810  0.0  0.0      0     0 ?        I    Feb22   0:01 [kworker/29:2-events]
root      872828  0.0  0.0      0     0 ?        I    Feb22   0:03 [kworker/42:0-mm_percpu_wq]
root      891238  0.0  0.0      0     0 ?        I    Feb22   0:01 [kworker/27:0-mm_percpu_wq]
root      891249  0.0  0.0      0     0 ?        I    Feb22   0:01 [kworker/46:0-events]
root      997758  0.0  0.0      0     0 ?        I    Feb23   0:00 [kworker/15:2-mm_percpu_wq]
root     1090953  0.0  0.0      0     0 ?        I    Feb23   0:00 [kworker/1:1-events]
root     1091297  0.0  0.0      0     0 ?        I    Feb23   0:00 [kworker/44:1-mm_percpu_wq]
root     1139150  0.0  0.0      0     0 ?        I    Feb23   0:02 [kworker/34:1-events]
root     1139597  0.0  0.0      0     0 ?        I    Feb23   0:04 [kworker/18:1-mm_percpu_wq]
root     1149519  0.0  0.0      0     0 ?        I    Feb24   0:00 [kworker/7:2-ipv6_addrconf]
root     1151916  0.0  0.0      0     0 ?        I    Feb24   0:00 [kworker/36:0-events]
root     1152169  0.0  0.0      0     0 ?        I    Feb24   0:01 [kworker/23:2-events]
root     1192958  0.0  0.0      0     0 ?        I    Feb24   0:00 [kworker/30:0-events]
root     1226273  0.0  0.0      0     0 ?        I    Feb24   0:00 [kworker/31:0-events]
root     1235061  0.0  0.0      0     0 ?        I    Feb24   0:00 [kworker/33:0-events]
root     1235063  0.0  0.0      0     0 ?        I    Feb24   0:00 [kworker/37:1-mm_percpu_wq]
root     1235809  0.0  0.0      0     0 ?        I    Feb24   0:00 [kworker/39:1-mm_percpu_wq]
root     1239469  0.0  0.0      0     0 ?        I    Feb24   0:00 [kworker/48:0-mm_percpu_wq]
root     1279203  0.0  0.0      0     0 ?        I    Feb24   0:00 [kworker/19:0-mm_percpu_wq]
root     1286125  0.0  0.0      0     0 ?        I    Feb24   0:00 [kworker/55:2-mm_percpu_wq]
root     1350499  0.0  0.0      0     0 ?        I    Feb25   0:00 [kworker/35:2-mm_percpu_wq]
root     1379987  0.0  0.0      0     0 ?        I    Feb25   0:00 [kworker/47:1-mm_percpu_wq]
root     1407120  0.0  0.0      0     0 ?        I    Feb25   0:00 [kworker/17:2-events]
root     1407122  0.0  0.0      0     0 ?        I    Feb25   0:00 [kworker/41:1-mm_percpu_wq]
root     1407123  0.0  0.0      0     0 ?        I    Feb25   0:00 [kworker/9:0-mm_percpu_wq]
root     1418355  0.0  0.0      0     0 ?        I    Feb25   0:00 [kworker/45:1-events]
root     1419245  0.0  0.0      0     0 ?        I    Feb25   0:01 [kworker/4:0-events]
root     1430133  0.0  0.0      0     0 ?        I    Feb25   0:00 [kworker/49:2-mm_percpu_wq]
root     1432474  0.0  0.0      0     0 ?        I    Feb25   0:00 [kworker/53:2-rcu_gp]
root     1432497  0.0  0.0      0     0 ?        I    Feb25   0:00 [kworker/11:0-mm_percpu_wq]
root     1435643  0.0  0.0      0     0 ?        I    Feb25   0:00 [kworker/28:1-events]
root     1445978  0.0  0.0      0     0 ?        I    Feb25   0:02 [kworker/0:2-events]
root     1448397  0.0  0.0      0     0 ?        I    Feb25   0:01 [kworker/2:1-events]
root     1459842  0.0  0.0      0     0 ?        I    Feb25   0:00 [kworker/38:2-events]
root     1468183  0.0  0.0      0     0 ?        I    Feb25   0:00 [kworker/15:0]
root     1477095  0.0  0.0      0     0 ?        I    Feb25   0:00 [kworker/19:2-events]
root     1481344  0.0  0.0      0     0 ?        I    Feb25   0:00 [kworker/39:0]
root     1481447  0.0  0.0      0     0 ?        I    Feb25   0:00 [kworker/17:0-events]
root     1491953  0.0  0.0      0     0 ?        I    Feb25   0:00 [kworker/21:0-events]
root     1492199  0.0  0.0      0     0 ?        I    Feb25   0:00 [kworker/3:0-mm_percpu_wq]
root     1497315  0.0  0.0      0     0 ?        I    00:00   0:00 [kworker/5:1-mm_percpu_wq]
root     1497354  0.0  0.0      0     0 ?        I    00:00   0:00 [kworker/51:2-events]
root     1500790  0.0  0.0      0     0 ?        I    00:28   0:00 [kworker/43:1]
root     1502040  0.0  0.0      0     0 ?        I    00:39   0:00 [kworker/5:2]
root     1504314  0.0  0.0      0     0 ?        I    00:59   0:00 [kworker/13:2-events]
root     1506107  0.0  0.0      0     0 ?        I    01:14   0:00 [kworker/7:1-events]
root     1506390  0.0  0.0      0     0 ?        I    01:17   0:00 [kworker/53:1-mm_percpu_wq]
root     1507206  0.0  0.0      0     0 ?        I    01:23   0:00 [kworker/u113:3-flush-253:0]
root     1508088  0.0  0.0      0     0 ?        I    01:31   0:00 [kworker/22:2-events]
root     1508128  0.0  0.0      0     0 ?        I    01:31   0:00 [kworker/32:2]
root     1508148  0.0  0.0      0     0 ?        I    01:31   0:00 [kworker/8:1-events]
root     1508351  0.0  0.0      0     0 ?        I    01:33   0:00 [kworker/1:0-events]
root     1509238  0.0  0.0      0     0 ?        I    01:40   0:00 [kworker/40:0]
root     1509319  0.0  0.0      0     0 ?        I    01:41   0:00 [kworker/54:2-events]
root     1509539  0.0  0.0      0     0 ?        I    01:43   0:00 [kworker/55:0]
root     1510518  0.0  0.0      0     0 ?        I    01:51   0:00 [kworker/42:1-events]
root     1511821  0.0  0.0      0     0 ?        I    02:02   0:00 [kworker/3:1-events]
root     1512300  0.0  0.0      0     0 ?        I    02:06   0:00 [kworker/24:0-events]
root     1513401  0.0  0.0      0     0 ?        I    02:16   0:00 [kworker/16:0-cgroup_destroy]
root     1513442  0.0  0.0      0     0 ?        I    02:16   0:00 [kworker/u114:1-flush-253:0]
root     1513524  0.0  0.0      0     0 ?        I    02:17   0:00 [kworker/23:1-events]
root     1513963  0.0  0.0      0     0 ?        I    02:21   0:00 [kworker/36:2-events]
root     1514259  0.0  0.0      0     0 ?        I    02:23   0:00 [kworker/29:1-cgroup_destroy]
root     1514339  0.0  0.0      0     0 ?        I    02:24   0:00 [kworker/34:2-cgroup_destroy]
root     1514421  0.0  0.0      0     0 ?        I    02:25   0:00 [kworker/37:0-cgroup_destroy]
root     1514441  0.0  0.0      0     0 ?        I    02:25   0:00 [kworker/31:2-events]
root     1514442  0.0  0.0      0     0 ?        I    02:25   0:00 [kworker/u114:3-flush-253:0]
root     1514464  0.0  0.0      0     0 ?        I    02:25   0:00 [kworker/41:2-cgroup_destroy]
root     1514663  0.0  0.0      0     0 ?        I    02:27   0:00 [kworker/52:0-events]
root     1514766  0.0  0.0      0     0 ?        I    02:27   0:00 [kworker/30:1-events]
root     1514826  0.0  0.0      0     0 ?        I    02:28   0:00 [kworker/u113:2-events_unbound]
root     1514865  0.0  0.0      0     0 ?        I    02:28   0:00 [kworker/18:0]
root     1514987  0.0  0.0      0     0 ?        I    02:29   0:00 [kworker/6:0-events]
root     1515207  0.0  0.0      0     0 ?        I    02:31   0:00 [kworker/46:1-cgroup_destroy]
root     1515227  0.0  0.0      0     0 ?        I    02:31   0:00 [kworker/33:1-events]
root     1515271  0.0  0.0      0     0 ?        I    02:32   0:00 [kworker/35:0-events]
root     1515310  0.0  0.0      0     0 ?        I    02:32   0:00 [kworker/48:1-events]
root     1515369  0.0  0.0      0     0 ?        I    02:33   0:00 [kworker/20:1-events]
root     1515431  0.0  0.0      0     0 ?        I    02:33   0:00 [kworker/50:0-events]
root     1515591  0.0  0.0      0     0 ?        I    02:34   0:00 [kworker/44:2]
root     1515631  0.0  0.0      0     0 ?        I    02:35   0:00 [kworker/49:0]
root     1515652  0.0  0.0      0     0 ?        I    02:35   0:00 [kworker/11:2-events]
root     1515776  0.0  0.0      0     0 ?        I    02:36   0:00 [kworker/u114:2-flush-253:0]
root     1515816  0.0  0.0      0     0 ?        I    02:36   0:00 [kworker/27:2-cgroup_destroy]
root     1515937  0.0  0.0      0     0 ?        I    02:37   0:00 [kworker/9:2-events]
root     1515977  0.0  0.0      0     0 ?        I    02:38   0:00 [kworker/51:0-events]
root     1516075  0.0  0.0      0     0 ?        I    02:39   0:00 [kworker/14:1]
root     1516119  0.0  0.0      0     0 ?        I    02:39   0:00 [kworker/25:0-events]
root     1516180  0.0  0.0      0     0 ?        I    02:39   0:00 [kworker/10:1-cgroup_destroy]
root     1516276  0.0  0.0      0     0 ?        I    02:40   0:00 [kworker/38:0-cgroup_destroy]
root     1516298  0.0  0.0      0     0 ?        I    02:40   0:00 [kworker/45:2-events]
root     1516319  0.0  0.0      0     0 ?        I    02:41   0:00 [kworker/u113:1-events_unbound]
root     1516340  0.0  0.0      0     0 ?        I    02:41   0:00 [kworker/26:2]
root     1516400  0.0  0.0      0     0 ?        I    02:41   0:00 [kworker/12:1-events]
root     1516479  0.0  0.0      0     0 ?        I    02:42   0:00 [kworker/4:2-cgroup_destroy]
root     1516522  0.0  0.0      0     0 ?        I    02:42   0:00 [kworker/2:2-events]
root     1516543  0.0  0.0      0     0 ?        I    02:42   0:00 [kworker/0:0-events]
root     1516582  0.0  0.0      0     0 ?        I    02:43   0:00 [kworker/47:0-events]
root     1516643  0.0  0.0      0     0 ?        I    02:43   0:00 [kworker/u114:0-flush-253:0]
root     1516664  0.0  0.0      0     0 ?        I    02:44   0:00 [kworker/37:2-events]
root     1516841  0.0  0.0      0     0 ?        I    02:45   0:00 [kworker/41:0-events]
root     1516861  0.0  0.0      0     0 ?        I    02:45   0:00 [kworker/34:0-events]
root     1516902  0.0  0.0      0     0 ?        I    02:46   0:00 [kworker/u113:0-events_unbound]
root     1516960  0.0  0.0      0     0 ?        I    02:46   0:00 [kworker/10:0-events]
root     1516983  0.0  0.0      0     0 ?        I    02:46   0:00 [kworker/29:0-events]
root     1517043  0.0  0.0      0     0 ?        I    02:47   0:00 [kworker/27:1-events]
root     1517145  0.0  0.0      0     0 ?        I    02:48   0:00 [kworker/4:1-events]
root     1517165  0.0  0.0      0     0 ?        I    02:48   0:00 [kworker/46:2]
root     1517166  0.1  0.0  17180 10844 ?        Ss   02:48   0:00 sshd: henry [priv]
henry    1517188  0.7  0.0  17076  9776 ?        Ss   02:48   0:00 /lib/systemd/systemd --user
henry    1517189  0.0  0.0 170608  5188 ?        S    02:48   0:00 (sd-pam)
root     1517194  0.0  0.0      0     0 ?        I    02:48   0:00 [kworker/16:2-events]
henry    1517294  0.0  0.0  17312  8008 ?        R    02:48   0:00 sshd: henry@pts/0
henry    1517295  0.1  0.0   8868  5376 pts/0    Ss   02:48   0:00 -bash
root     1517332  0.0  0.0      0     0 ?        I    02:48   0:00 [kworker/38:1-events]
henry    1517333  0.0  0.0  10336  3732 pts/0    R+   02:48   0:00 ps -aux
henry@cp:~$ sudo rtcwake -m mem -s 36000
[sudo] password for henry: 
Sorry, try again.
[sudo] password for henry: 
rtcwake: assuming RTC uses UTC ...
rtcwake: wakeup from "mem" using /dev/rtc0 at Wed Feb 26 12:50:12 2025
Read from remote host 192.168.1.105: Operation timed out
Connection to 192.168.1.105 closed.
client_loop: send disconnect: Broken pipe

    ~ ·············································································· 255 ✘  took 2m 25s   at 09:50:48 PM  ─╮
❯ ls                                                                                                                               ─╯
Applications  LFS258_V2024-03-14_SOLUTIONS.tar.xz  Public                            hr-vault-main-pa
Desktop       Library                              Sites                             kali-shelz
Documents     Movies                               git-runner-example.yml            packages.txt
Downloads     Music                                git-scriptrunner-outline-yaml.sh  suid-containerescape-example.sh
Github        Oracle                               go                                tmp
LFS258        Pictures                             go-shelz                          vault-main

    ~ ······································································································ at 09:51:12 PM  ─╮
❯ ls                                                                                                                               ─╯
Applications  LFS258_V2024-03-14_SOLUTIONS.tar.xz  Public                            hr-vault-main-pa
Desktop       Library                              Sites                             kali-shelz
Documents     Movies                               git-runner-example.yml            packages.txt
Downloads     Music                                git-scriptrunner-outline-yaml.sh  suid-containerescape-example.sh
Github        Oracle                               go                                tmp
LFS258        Pictures                             go-shelz                          vault-main

    ~ ············································································································ at 10:08:42 PM        ~ ·············································································································· at 10:08:42 PM  ─╮
❯ vim .zshrc                                                                                                                               ─╯








# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# zsh-completetions gh repo clone into zsh custom plugins.
fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src
export ZSH="$HOME/.oh-my-zsh"

# zsh-autosuggestions source/activiation - required before compinit is executed 
source $HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"


# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
".zshrc" 189L, 7691B
