git-sync
========

Synchronize mirror repositories locally from remote sources.
Helpful to maintain a mirror of projects located on various hosts such as GitHub or Gerrit.

Basic
-----

The 'git-sync' script takes a config.yml as a parameter which is formatted like this:

```
global:
    to: '/storage/git'
sources:
  - from: 'https://github.com/CoRfr/git-sync'
  - from: 'https://github.com/CoRfr/ruby-git'
    to: '/mnt/external/ruby-git.git'
  - type: 'gerrit'
    host: 'gerrit-host'
    username: 'myuser'
    from: 'git://gerrit-mirror/'
    filters:
      - 'manifest'
      - '/meta.*/'
```

Sources
-------

#### Single

Default (and simpliest) type. Will synchronize from a Git remote ('from') to some directory ('to').
If a default global 'to' is provided, path will be built using it plus the basename of the Git remote.

```
  - from: 'https://github.com/CoRfr/ruby-git'
    to: '/mnt/external/ruby-git.git'
```

#### Gerrit

Uses Gerrit SSH protocol to list projects and filter the ones to sync using strings or regex (as a string surrounded by '/').
You can optionally specify a mirror using 'from' if you don't want to overload the master.

```
  - type: 'gerrit'
    host: 'gerrit-host'
    username: 'myuser'
    from: 'git://gerrit-mirror/'
    filters:
      - 'manifest'
      - '/meta.*/'
```

By default the script will use the 'stream-events' command to listen for changes on project and re-synchronize them.
It is possible to specify the ```oneshot: true``` option, either in global or in the gerrit source definition to prevent the re-sync.

