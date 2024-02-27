# AlwaysShadow - a program for forcing Shadowplay's Instant Replay to stay on.
# Copyright (C) 2024 Aviv Edery.

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

CC:=gcc
BIN:=bin
SRC:=src
INCL:=include
RESRC:=resources
PROG:=$(BIN)/AlwaysShadow.exe
RELEASE:=$(BIN)/AlwaysShadow.zip
FLAGFILE:=$(BIN)/cflags.txt
TAGSFILE:=$(BIN)/tags.txt
VERSIONFILE:=version.txt
VERSIONBRANCH:=version

# Implement a fallback because I don't want gh to be a mandatory dependency for anything other than make release.
GITHUB_NAME_WITH_OWNER:=$(shell gh repo view --json nameWithOwner --jq '.[]' 2> /dev/null || echo Verpous/AlwaysShadow)

YELLOW_FG:=$(shell tput setaf 3)
NOCOLOR:=$(shell tput sgr0)

# Auto detect files we want to compile.
CFILES:=$(wildcard $(SRC)/*.c)
RFILES:=$(wildcard $(RESRC)/*.rc)

OBJS += $(patsubst $(SRC)/%.c,$(BIN)/%.o,$(CFILES))
OBJS += $(patsubst $(RESRC)/%.rc,$(BIN)/%.o,$(RFILES))

# Can't autodetect autogenerated files.
OBJS += $(BIN)/gen_tags.o

# Files generated by compiler for recompiling based on changed dependencies.
DEPENDS:=$(wildcard $(BIN)/*.d)

# The style of commenting below may seem funny but there's a reason, it's so the alignment spacing doesn't make the output ugly.
# C compiler flags.
CFLAGS += -c #							Compile, duh.
CFLAGS += -I $(INCL) #					Search for #includes in this folder.
CFLAGS += -Wall #						All warnings (minus the ones we'll subtract now).
CFLAGS += -Wno-unknown-pragmas #		For getting rid of warnings about regions in the code.
CFLAGS += -Wno-unused-function #		Some functions aren't used depending on #ifdefs.
CFLAGS += -fmacro-prefix-map=$(SRC)/= #	Makes it so in the logs only basenames of files are printed.
CFLAGS += -MMD -MP #					Generate *.d files, used for detecting if we need to recompile due to a change in included headers.
CFLAGS += -D CURL_STATICLIB #			Mandatory for statically linking curl.
CFLAGS += -D GITHUB_NAME_WITH_OWNER=\"$(GITHUB_NAME_WITH_OWNER)\" # 		For building links to the GitHub repo.
CFLAGS += -D VERSION_BRANCH_AND_FILE=\"$(VERSIONBRANCH)/$(VERSIONFILE)\" #	For downloading the latest version tag.

# Linker flags.
LFLAGS += -Wall #     All warnings.
LFLAGS += -mwindows # Makes it so when you run the program it doesn't open cmd.
LFLAGS += -static #   For static linking so people don't have problems (they've had a few).

# Libraries that we link.
LIBS += -lpthread #   For multithreading.
LIBS += -lwbemuuid #  For WMI to get the command line of processes. 
LIBS += -lole32 #     For COM to get the command line of processes.
LIBS += -loleaut32 #  For working with BSTRs.
LIBS += -luuid #      For FOLDERID_LocalAppData.
LIBS += -lshlwapi #   For path functions.

# Output of `pkg-config --libs --static regex`. It's regex and all its dependencies.
LIBS += -lregex
LIBS += -ltre
LIBS += -lintl

# Output by `pkg-config --libs --static libcurl`. It's libcurl and all its dependencies.
LIBS += -lcurl
LIBS += -lidn2
LIBS += -lssh2
LIBS += -lpsl
LIBS += -lbcrypt
LIBS += -ladvapi32
LIBS += -lcrypt32
LIBS += -lbcrypt
LIBS += -lwldap32
LIBS += -lzstd
LIBS += -lbrotlidec
LIBS += -lz
LIBS += -lws2_32
LIBS += -lidn2
LIBS += -liconv
LIBS += -lunistring
LIBS += -lbrotlidec
LIBS += -lbrotlicommon

# yes/no to unicode strings.
unicode = yes
ifeq ($(strip $(unicode)),yes)
	CFLAGS += -D UNICODE -D _UNICODE
endif

# yes/no to debug builds (grants instant log flushing mostly).
debug = no
ifeq ($(strip $(debug)),yes)
	CFLAGS += -D DEBUG_BUILD
endif

# If not empty, use this tag instead of downloading the latest one from curl (for debugging).
latest_tag = 
ifneq ($(strip $(latest_tag)),)
	CFLAGS += -D LATEST_TAG_OVERRIDE=\"$(latest_tag)\"
endif

# Either auto or a space-separated list of tags to function as the list of tags which existed when this build was compiled.
tags = auto

# List variables we want to print before compilation.
PRINT_VARS += unicode
PRINT_VARS += debug
PRINT_VARS += tags
PRINT_VARS += latest_tag

.PHONY: all release release_pre_build publish run runx log write_flagfile write_tags clean

# Makes a build. Order is important.
all: $(patsubst %,printvar-%,$(PRINT_VARS)) write_flagfile write_tags $(PROG)

# Prints a variable for debug purposes. Adding these rules to .PHONY makes them not run for some reason.
printvar-%:
	@printf "%s%-20s%s = %s\n" "$(YELLOW_FG)" "$*" "$(NOCOLOR)" "$($*)"

# Creates a release inside a zip and pushes it to GitHub.
release: clean release_pre_build all
	rm -f $(RELEASE)
	7z a -tzip $(RELEASE) ./$(PROG)
	gh release upload $$(./make_helpers.sh latest_release tagName) $(RELEASE)

	@echo "Release is ready as a draft. Go to GitHub, inspect it, run make publish when you're ready."

# Part of make release, do not run this directly. It's things we want to do before "all" (must create the new tag before "all" calls write_tags).
release_pre_build:
	gh release list

	@if [[ "$$(./make_helpers.sh latest_release isDraft)" == true ]]; then\
		./make_helpers.sh confirm "Detected that the lastest release is already a draft. Delete it?" && gh release delete $$(./make_helpers.sh latest_release tagName);\
	fi

	@echo "Reminder: usually tags are of the form 'v1.x', and titles are 'AlwaysShadow v1.x'"
	@echo "Prerelease no, draft YES ABSOLUTELY!"
	gh release create --draft --prerelease=false

	@[[ "$$(./make_helpers.sh latest_release tagName)" =~ ^v[0-9]+.[0-9]+$$ ]] || ./make_helpers.sh confirm "Tag is not of the form 'v<major>.<minor>'. Are you sure?"
	@[[ "$$(./make_helpers.sh latest_release name)" == "AlwaysShadow $$(./make_helpers.sh latest_release tagName)" ]] || ./make_helpers.sh confirm "Title is not of the form 'AlwaysShadow <tag>'. Are you sure?"

# Publishes a drafted release.
publish:
	[[ "$$(git branch --show-current)" != $(VERSIONBRANCH) ]]
	[[ "$$(./make_helpers.sh latest_release isDraft)" == true ]]

	# make_helpers.sh won't exist once we checkout branches so we need to store this now.
	$(eval TAG:=$(shell ./make_helpers.sh latest_release tagName))

	@./make_helpers.sh confirm "Release $(TAG) will be published. Are you sure?"
	@./make_helpers.sh confirm "Are you ABSOLUTELY sure?"

	git add .
	git stash
	git checkout -B $(VERSIONBRANCH) origin/$(VERSIONBRANCH)
	echo -n "$(TAG)" > $(VERSIONFILE)

	git add .
	git commit -m 'version $(TAG)'

	git checkout master
	git stash pop -q
	git restore --staged .

	gh release edit --draft $(TAG)
	git push origin $(VERSIONBRANCH) || { echo "****FAILED TO PUSH $(VERSIONFILE) AFTER PUBLISHING RELEASE. FIX THIS ASAP****"; false; }

# Writes CFLAGS to a file only if it's changed from the last run. We use this to recompile binaries when changing to/from debug builds.
# Important that this target isn't simply called $(FLAGFILE), that's a different target which we use.
write_flagfile:
	echo "$(CFLAGS)" | ./make_helpers.sh write_if_diff $(FLAGFILE)

# Same deal as with cflags, we want to recompile gen_tags.c only if the tags have changed on github.
# Support override of tags list for debugging purposes.
ifeq ($(strip $(tags)),auto)
write_tags:
	gh release list --json tagName --jq '.[] | .tagName' 2> /dev/null | ./make_helpers.sh write_if_diff $(TAGSFILE)
else
write_tags:
	printf '%s\n' $(tags) | ./make_helpers.sh write_if_diff $(TAGSFILE)
endif

# Compiles and runs. Output streams are redirected to a log.
run: all runx

# "Run exclusively". Same as run, but won't try to compile it.
runx:
	$(PROG) & pid=$$!; ./make_helpers.sh confirm "Press Y when you're ready to kill it..." && kill $$pid

# View latest logs as they come.
log:
	tail -f "$$LOCALAPPDATA"/AlwaysShadow/output.log

# Deletes values stored in the registry and empties the bin folder.
clean:
	MSYS_NO_PATHCONV=1 reg delete HKCU\\Software\\AlwaysShadow /f 2> /dev/null || true
	rm -f $(BIN)/*

include $(DEPENDS)

# The rules below do the actual job of compiling and linking all the different files. You'll probably never run them directly.

# Create the final exe.
$(PROG): $(OBJS)
	$(CC) $(LFLAGS) $(OBJS) $(LIBS) -o $@

# Compile .c files.
$(BIN)/%.o: */%.c $(FLAGFILE) | $(BIN)
	$(CC) $(CFLAGS) -o $@ $<

# Compile .rc files.
# For .c files we are able to autogenerate dependency files, but for .rc files we can't so we'll just make it depend on all headers.
$(BIN)/%.o: */%.rc $(INCL)/*.h | $(BIN)
	windres -Iinclude -o $@ $<

# Autogenerated code.
# This adds the tag "tagName" to the list of tags, but there's no reason to care.
$(BIN)/gen_tags.c: $(TAGSFILE) | $(BIN)
	awk '\
		BEGIN	{ print "// AUTOGENERATED FILE. DO NOT MODIFY.";\
				  print "#include \"defines.h\"";\
				  print "const char *tags[] = {" }\
		1 		{ print "    \"" $$0 "\"," }\
		END 	{ print "};";\
				  print "const size_t tagsLen = _countof(tags);" }' $< > $@

# Need that bin folder.
$(BIN):
	mkdir -p $@
