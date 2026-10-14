# nopaystation\_scripts

A shell script collection which downloads nopaystation PS Vita stuff.
There are several scripts. One to download all \*.tsv files of NoPayStation. The other are for downloading games, updates
or all DLC of a PS Vita game, PSM or PSP games.

## Supported Operating Systems
* GNU/Linux
* FreeBSD
* Windows 10 with WSL should also work but it's untested

## Requirements
* a working internet connection
* posix shell (bash, ksh, zsh, sh)
* curl or wget
* [*pkg2zip*](https://github.com/lusid1/pkg2zip) (please migrate to lusid1's fork as mmozeiko abandoned his project)
* latest [*torrent7z*](https://github.com/BubblesInTheTub/torrent7z)
* python3 + python3-lxml (install it via package manager or pip)
* (Optional) latest [*mktorrent*](https://github.com/Rudde/mktorrent)


## Compiling dependencies from source
This section assumes that "${HOME}/bin" is in your shells "${PATH}".
If you don't want to install the generating programs in $HOME. Just
change it in the howto below to something like "/usr/local/bin" etc.

### mktorrent
If your package manager doesn't already have v1.1 you can compile it by yourself.
mktorrent v1.1 is only needed for source flag. If you don't need it you also can use v1.0.
You also need some sort of compiler (e.g. gcc) and "make" is needed.
```bash
git clone https://github.com/Rudde/mktorrent.git
cd mktorrent/ && PREFIX=$HOME make
PREFIX="${HOME}" make install
rm -rf ~/mktorrent
```

### t7z
Compile t7z from source (gcc and make is needed).
```bash
git clone https://github.com/BubblesInTheTub/torrent7z
cd torrent7z/linux_src/p7zip_4.65/
make
install -Dm 0755 bin/t7z "${HOME}/bin"
```

## nopaystation\_scripts Installation
```bash
git clone https://github.com/sigmaboy/nopaystation_scripts.git && cd nopaystation_scripts
chmod +x nps_*.sh pyNPU.py
test -d "${HOME}/bin" && ln -s "$(pwd)"/nps_*.sh "$(pwd)"/pyNPU.py "${HOME}/bin"
```

If you don't have *${HOME}/bin* in your *${PATH}*, try the following.
```bash
test -d "/usr/local/bin" && sudo ln -s "$(pwd)"/nps_*.sh "$(pwd)"/pyNPU.py "/usr/local/bin/"
```

## Directory configuration

Copy `config.example` to `~/.config/nopaystation/config`. The three settings are independent:

```sh
NPS_DOWNLOAD_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/nopaystation/downloads"
NPS_EXTRACT_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/nopaystation/extract"
NPS_OUTPUT_DIR="${HOME}/Downloads/nopaystation"
NPS_CHECKSUM_MISMATCH_ACTION="no"
```

`NPS_DOWNLOAD_DIR` stores temporary network downloads, `NPS_EXTRACT_DIR` stores temporary unpacked files, and `NPS_OUTPUT_DIR` receives final archives, changelogs, and collection directories. Temporary per-run directories are removed after successful completion. If the config file is absent, all three default to the directory where the command was started. An environment variable with the same name overrides the config for one command.

Checksum mismatches abort without prompting by default and remove the downloaded file. Set `NPS_CHECKSUM_MISMATCH_ACTION=yes` to continue despite a mismatch, or `NPS_CHECKSUM_MISMATCH_ACTION=prompt` to ask interactively. An environment value overrides the fixed configuration for that command.

## Script examples

### nps\_tsv.sh
It downloads every \*.tsv file from NoPayStation.com and creates a tar archive with the current date for it.
```bash
./nps_tsv.sh /path/to/the/output_directory
```
If you don't add the output directory as the first parameter, it uses `NPS_OUTPUT_DIR`.
You need the \*.tsv file(s) for mostly every other script in this toolset.

### nps\_game.sh
With this script you can download a PS Vita game.
The first parameter is the path to your \*.tsv file and the second is the game's title ID.
It places the \*.7z (torrent7z) file in the current directory.
It also changes the region name into TV format (NTSC, PAL, ...)
For example:
```bash
./nps_game.sh /home/tux/Downloads/GAME.tsv PCSE00986
```
I can recommend [this](http://renascene.com/psv/) site for searching title IDs.

### nps\_update.sh
With this script you can download the latest or all available PS Vita game updates.
There is a optional first parameter "-a" and the second is the game's title ID.
It places files under `NPS_OUTPUT_DIR` in `<Game Name> [<TITLE_ID>] [<Region>]_update`, reusing existing named or legacy `<TITLE_ID>_update` folders. `DESTDIR` overrides the folder name. Each patch is checked by title ID and version before downloading: old versions do not prevent downloading the latest, and `-a` fills in every missing version. All requested versions already present returns exit code 5; any new downloads return 0. Folders are not renamed or nested on repeat runs.
For example:
```bash
./nps_update.sh [-a] PCSE00986
```

`pyNPU.py --link --with-version --title-id PCSE00986` prints tab-separated version/URL records for these checks; add `--all` for every version. Ordinary `--link` output remains one URL per line. Run the offline regression suite with `python3 -m unittest discover -s tests`.

### nps\_dlc.sh
This script downloads every DLC found for a specific title ID with available zRIF key.
Every update is placed in a created directory from the current working directory named <\TITLE\_ID\_update>.
For example:
```bash
./nps_dlc.sh /home/tux/Downloads/DLC.tsv PCSE00986
```
Every DLC is placed in `<TITLE_ID>_dlc` under `NPS_OUTPUT_DIR`. Existing archives are matched individually by title ID and the DLC identifier from the TSV Content ID column, so rerunning downloads only missing DLCs. When Content ID is unavailable, the script checks the exact archive name after downloading the package. Exit code 5 means every available DLC is already present; downloading any missing DLC returns 0, unless links or keys are missing (4).

Run the offline DLC regression tests with `python3 -m unittest discover -s tests`. The tests use mock download and packaging tools, including repeat runs of `nps_region.sh -r JP -d . -t dlc`.

### nps\_psm.sh
With this script you can download a PSM game.
The first parameter is the path to your \*.tsv file and the second is the game's title ID.
It places the the \*.7z (torrent7z) file in the current directory.
It also changes the region name into TV format (NTSC, PAL, ...)
For example:
```bash
./nps_psm.sh /home/tux/Downloads/PSM.tsv NPSA00115
```

### nps\_psp.sh
With this script you can download a PSP game.
The first parameter is the path to your \*.tsv file and the second is the game's title ID.
It places the \*.iso file in the current directory.
For example:
```bash
./nps_psp.sh /home/tux/Downloads/PSP_GAMES.tsv NPUZ00001
```
I can recommend [this](http://renascene.com/psp/) site for searching title IDs.

### nps\_bundle.sh
Requirements:
* pkg2zip and the optionally mktorrent If you want to use the source flag, you need mktorrent >= 1.1

This script downloads the game, every update and dlc found for a specific title ID with available zRIF key.
It puts the DLC and the Updates in a dedicated folder named like the generated zip and optionally creates a torrent for the game,
updates and dlc folders. In fact it uses the three scripts from above, combines them and download everything available for a game.
You need to have nps\_game.sh, nps\_update.sh, nps\_dlc.sh in your $PATH variable to get it working.

You need to symlink them to **${HOME}/bin/**, **/usr/local/bin** or **/usr/bin/**.
This is explained in the *Installation* Section above

If you want to do some additional steps after running *nps_bundle.sh*, you can add a post script named *nps_bundle_post.sh* to the directory where you run *nps_bundle.sh* from the command line.
It has to be executable to run. *nps_bundle.sh* runs the post script with the game name as the first parameter.
Your script can handle the parameter with the variable **$1** in your (shell) script.
You can use this to automate your upload process with an script which adds the torrent to your client or move it and
set the correct permissions to the file.
All files are named like **$1**.
For example the update and dlc directories
* ${1}_update
* ${1}_dlc

or the torrent files
* ${1}.torrent
* ${1}_update.torrent
* ${1}_dlc.torrent

If you call the script with "-a", it will download all updates instead of the latest only. Additionally you can set the parameter [-c]
to enable torrent creating. If you use this you can add source flag after it.
when creating torrent files with to use with private trackers.
To use this feature you need to have mktorrent installed in version 1.1+!
For example:
```bash
./nps_bundle.sh [-a] -t PCSE00986 -c "http://announce.url" -d "/path/to/directory/containing/the/tsv/files" [-c] [<SOURCE FLAG>]
```

## nps\_region.sh
This works pretty much the same as **nps_bundle.sh** but downloads all base games of a specific region.
It creates a subdirectory in your current working directory for the region you mentioned. Valid regions are *US* *JP* *EU* *ASIA*.
There is also a post hook implemented with the file name *./nps_region_post.sh* like *nps\_bundle*. The name of the collection directory
is overgiven to the post script as the first parameter.
For more informations and help about the script just call it with the *--help* parameter or look at the code.

Example:
```bash
$ ./nps_region.sh -r ASIA -t game -d /path/to/directory/containing/the/tsv/files [-c http://announce.url] [-s <SOURCE>] [-a]
```

### pyNPU.py
This little python program helps you downloading updates and generating changelogs for your games.
Just use the "-h" parameter to get all parameters and examples. It's useful for checking changelogs and generating download links.

# ToDos
* add command line parameters to control the behaviour of the download scripts (downloading/compressing only)
* compare the whole download + compression process of pkg2zip vs. pkg2zip without zipping + torrent7z compressing
