# Makefile to build the entire dlang.org website
#
# To run:
#
# make -f posix.mak all
#
# To also upload to the website:
#
# make -f posix.mak rsync
#

PWD=$(shell pwd)

# Latest released version
ifeq (,${LATEST})
LATEST:=$(shell cat VERSION)
endif
# Next major DMD release
NEXT_VERSION:=$(shell bash -c 'version=$$(cat VERSION);a=($${version//./ });a[1]="10\#$${a[1]}";((a[1]++)); a[2]=0; echo $${a[0]}.0$${a[1]}.$${a[2]};' )

# DLang directories
DMD_DIR=../dmd
PHOBOS_DIR=../phobos
DRUNTIME_DIR=../druntime
TOOLS_DIR=../tools
INSTALLER_DIR=../installer

include $(DMD_DIR)/src/osmodel.mak

# External binaries
DMD=$(DMD_DIR)/generated/$(OS)/release/$(MODEL)/dmd

# External directories
DOC_OUTPUT_DIR:=$(PWD)/web
GIT_HOME=https://github.com/dlang
DPL_DOCS_PATH=dpl-docs
DPL_DOCS=$(DPL_DOCS_PATH)/dpl-docs
REMOTE_DIR=d-programming@digitalmars.com:data
TMP?=/tmp

# Last released versions
DMD_LATEST_DIR=${DMD_DIR}-${LATEST}
DMD_LATEST=$(DMD_LATEST_DIR)/generated/$(OS)/release/$(MODEL)/dmd
DRUNTIME_LATEST_DIR=${DRUNTIME_DIR}-${LATEST}
PHOBOS_LATEST_DIR=${PHOBOS_DIR}-${LATEST}

# Auto-cloning missing directories
$(shell [ ! -d $(DMD_DIR) ] && git clone --depth=1 ${GIT_HOME}/dmd $(DMD_DIR))
$(shell [ ! -d $(DRUNTIME_DIR) ] && git clone --depth=1 ${GIT_HOME}/druntime $(DRUNTIME_DIR))

# Keep during the ddmd -> dmd transition
DMD_SRC_NAME=$(shell if [ -d $(DMD_DIR)/src/ddmd ] ; then echo "ddmd" ; else echo "dmd"; fi)

################################################################################
# Automatically generated directories
GENERATED=.generated
G=$(GENERATED)
PHOBOS_DIR_GENERATED=$(GENERATED)/phobos-prerelease
PHOBOS_LATEST_DIR_GENERATED=$(GENERATED)/phobos-release
# The assert_writeln_magic tool transforms all source files from Phobos. Hence
# - a temporary folder with a copy of Phobos needs to be generated
# - a list of all files in Phobos and the temporary copy is needed to setup proper
#   Makefile dependencies and rules
PHOBOS_FILES := $(shell find $(PHOBOS_DIR) -name '*.d' -o -name '*.mak' -o -name '*.ddoc')
PHOBOS_FILES_GENERATED := $(subst $(PHOBOS_DIR), $(PHOBOS_DIR_GENERATED), $(PHOBOS_FILES))
$(shell [ ! -d $(PHOBOS_DIR) ] && git clone --depth=1 ${GIT_HOME}/phobos $(PHOBOS_DIR))
$(shell [ ! -d $(PHOBOS_LATEST_DIR) ] && git clone -b v${LATEST} --depth=1 ${GIT_HOME}/phobos $(PHOBOS_LATEST_DIR))
PHOBOS_LATEST_FILES := $(shell find $(PHOBOS_LATEST_DIR) -name '*.d' -o -name '*.mak' -o -name '*.ddoc')
PHOBOS_LATEST_FILES_GENERATED := $(subst $(PHOBOS_LATEST_DIR), $(PHOBOS_LATEST_DIR_GENERATED), $(PHOBOS_LATEST_FILES))
################################################################################

# stable dub and dmd versions used to build dpl-docs
STABLE_DMD_VER=2.072.2
STABLE_DMD_ROOT=$(GENERATED)/stable_dmd-$(STABLE_DMD_VER)
STABLE_DMD_URL=http://downloads.dlang.org/releases/2.x/$(STABLE_DMD_VER)/dmd.$(STABLE_DMD_VER).$(OS).zip
STABLE_DMD_BIN_ROOT=$(STABLE_DMD_ROOT)/dmd2/$(OS)/$(if $(filter $(OS),osx),bin,bin$(MODEL))
STABLE_DMD=$(STABLE_DMD_BIN_ROOT)/dmd
STABLE_DMD_CONF=$(STABLE_DMD).conf
STABLE_RDMD=$(STABLE_DMD_BIN_ROOT)/rdmd --compiler=$(STABLE_DMD) -conf=$(STABLE_DMD_CONF)
DUB=$(STABLE_DMD_BIN_ROOT)/dub

# exclude lists
MOD_EXCLUDES_PRERELEASE=$(addprefix --ex=, gc. rt. core.internal. core.stdc.config core.sys.	\
	std.algorithm.internal std.c. std.concurrencybase std.internal. std.regex.internal.  \
	std.windows.iunknown std.windows.registry etc.linux.memoryerror	\
	std.experimental.ndslice.internal std.stdiobase \
	std.typetuple \
	tk. msvc_dmc msvc_lib \
	$(DMD_SRC_NAME).libmach $(DMD_SRC_NAME).libmscoff $(DMD_SRC_NAME).objc_glue \
	$(DMD_SRC_NAME).scanmach $(DMD_SRC_NAME).scanmscoff)

MOD_EXCLUDES_RELEASE=$(MOD_EXCLUDES_PRERELEASE)

# rdmd must fetch the model, imports, and libs from the specified version
DFLAGS=-m$(MODEL) -I$(DRUNTIME_DIR)/import -I$(PHOBOS_DIR) -L-L$(PHOBOS_DIR)/generated/$(OS)/release/$(MODEL)
RDMD=rdmd --compiler=$(DMD) $(DFLAGS)

# Tools
REBASE = MYBRANCH=`git rev-parse --abbrev-ref HEAD` &&\
 git checkout master &&\
 git pull --ff-only git@github.com:dlang/$1.git master &&\
 git checkout $$MYBRANCH &&\
 git rebase master

CHANGE_SUFFIX = \
 for f in `find "$3" -iname '*.$1'`; do\
  mv $$f `dirname $$f`/`basename $$f .$1`.$2; done

# Caches the latest D blog post for the front page
DBLOG_LATEST=

# Disable all dynamic content that could potentially have an unrelated impact
# on a diff
ifeq (1,$(DIFFABLE))
	NODATETIME := nodatetime.ddoc
	DPL_DOCS_PATH_RUN_FLAGS := --no-exact-source-links
else
	CHANGELOG_VERSION_MASTER := "v${LATEST}..upstream/master"
	CHANGELOG_VERSION_LATEST := "v${LATEST}..upstream/stable"
	DBLOG_LATEST=$G/dblog_latest.ddoc $G/twid_latest.ddoc
endif

################################################################################
# Ddoc build variables
################################################################################
DDOC_VARS_LATEST_HTML=\
	  DOC_OUTPUT_DIR="${DOC_OUTPUT_DIR}/phobos" \
	  STDDOC="$(addprefix $(PWD)/, $(STD_DDOC))" \
	  DMD="$(abspath $(DMD_LATEST))" \
	  DMD_DIR="$(abspath ${DMD_LATEST_DIR})" \
	  DRUNTIME_PATH="$(abspath ${DRUNTIME_LATEST_DIR})" \
	  DOCSRC="$(PWD)" \
	  VERSION="$(abspath ${DMD_DIR}/VERSION)"

DDOC_VARS=\
	DMD="$(abspath ${DMD})" \
	DMD_DIR="$(abspath ${DMD_DIR})" \
	DRUNTIME_PATH="$(abspath ${DRUNTIME_DIR})" \
	DOCSRC="$(PWD)" \
	VERSION="$(abspath ${DMD_DIR}/VERSION)"

DDOC_VARS_HTML=$(DDOC_VARS) \
	DOC_OUTPUT_DIR="${DOC_OUTPUT_DIR}/phobos-prerelease" \
	STDDOC="$(addprefix $(PWD)/, $(STD_DDOC_PRE))"

DDOC_VARS_VERBATIM=$(DDOC_VARS) \
	DOC_OUTPUT_DIR="${DOC_OUTPUT_DIR}/phobos-prerelease-verbatim" \
	STDDOC="$(PWD)/verbatim.ddoc"

################################################################################
# Resources
################################################################################

# Set to 1 in the command line to minify css files
CSS_MINIFY=

ORGS_USING_D=$(wildcard images/orgs-using-d/*)
IMAGES=favicon.ico $(ORGS_USING_D) $(addprefix images/, \
	d002.ico \
	$(addprefix compiler-, dmd.png gdc.svg ldc.png) \
	$(addsuffix .svg, icon_minus icon_plus hamburger dlogo faster-aa-1 faster-gc-1 \
		dconf_logo_2017 qualifier-combinations qualifier-conversions) \
	$(addsuffix .png, archlinux_logo apple_logo centos_logo chocolatey_logo \
		d3 debian_logo dlogo fedora_logo freebsd_logo gentoo_logo homebrew_logo \
		opensuse_logo ubuntu_logo windows_logo pattern github-ribbon \
		dlogo_opengraph \
		$(addprefix ddox/, alias class enum enummember function \
			inherited interface module package private property protected \
			struct template variable)) \
	$(addsuffix .gif, c1 cpp1 d4 d5 dmlogo dmlogo-smaller globe style3 \
		pen) \
	$(addsuffix .jpg, dman-error dman-rain dman-time tdpl))

JAVASCRIPT=$(addsuffix .js, $(addprefix js/, \
	codemirror-compressed dlang ddox listanchors platform-downloads run \
	run_examples show_contributors jquery-1.7.2.min))

STYLES=$(addsuffix .css, $(addprefix css/, \
	style print codemirror ddox))

################################################################################
# HTML Files
################################################################################

DDOC=$(addsuffix .ddoc, macros html dlang.org doc ${GENERATED}/${LATEST}) $(NODATETIME) $(DBLOG_LATEST)
STD_DDOC=$(addsuffix .ddoc, macros html dlang.org ${GENERATED}/${LATEST} std std_navbar-release ${GENERATED}/modlist-${LATEST}) $(NODATETIME)
STD_DDOC_PRE=$(addsuffix .ddoc, macros html dlang.org ${GENERATED}/${LATEST} std std_navbar-prerelease ${GENERATED}/modlist-prerelease) $(NODATETIME)
SPEC_DDOC=${DDOC} spec/spec.ddoc
CHANGELOG_DDOC=${DDOC} changelog/changelog.ddoc $(NODATETIME)
CHANGELOG_PRE_DDOC=${CHANGELOG_DDOC} changelog/prerelease.ddoc

PREMADE=appendices.html articles.html fetch-issue-cnt.php howtos.html	\
language-reference.html robots.txt .htaccess .dpl_rewrite_map.txt	\
d-keyring.gpg

# Language spec root filenames. They have extension .dd in the source
# and .html in the generated HTML. These are also used for the mobi
# book generation, for which reason the list is sorted by chapter.
SPEC_ROOT=$(addprefix spec/, \
	spec intro lex grammar module declaration type property attribute pragma	\
	expression statement arrays hash-map struct class interface enum	\
	const3 function operatoroverloading template template-mixin contracts		\
	version traits errors unittest garbage float iasm ddoc				\
	interfaceToC cpp_interface objc_interface portability entity memory-safe-d \
	abi simd betterc)
SPEC_DD=$(addsuffix .dd,$(SPEC_ROOT))

CHANGELOG_FILES=changelog/${NEXT_VERSION}_pre \
				$(basename $(subst _pre.dd,.dd,$(wildcard changelog/*.dd))) \

# Website root filenames. They have extension .dd in the source
# and .html in the generated HTML. Save for the expansion of
# $(SPEC_ROOT), the list is sorted alphabetically.
PAGES_ROOT=$(SPEC_ROOT) 404 acknowledgements areas-of-d-usage \
	articles ascii-table bugstats builtin \
	$(CHANGELOG_FILES) code_coverage community comparison concepts \
	const-faq cppcontracts cpptod ctarguments ctod donate \
	D1toD2 d-array-article d-floating-point deprecate dlangupb-scholarship dll-linux dmd \
	dmd-freebsd dmd-linux dmd-osx dmd-windows documentation download dstyle \
	exception-safe faq forum-template foundation gpg_keys glossary \
	gsoc2011 gsoc2012 gsoc2012-template hijack howto-promote htod index \
	intro-to-datetime lazy-evaluation menu migrate-to-shared mixin	\
	orgs-using-d overview pretod rationale rdmd regular-expression resources safed \
	search template-comparison templates-revisited tuple	\
	variadic-function-templates warnings wc windbg

TARGETS=$(addsuffix .html,$(PAGES_ROOT))

ALL_FILES_BUT_SITEMAP = $(addprefix $(DOC_OUTPUT_DIR)/, $(TARGETS)	\
$(PREMADE) $(STYLES) $(IMAGES) $(JAVASCRIPT))

ALL_FILES = $(ALL_FILES_BUT_SITEMAP) $(DOC_OUTPUT_DIR)/sitemap.html

################################################################################
# Rulez
################################################################################

all : docs html

docs-release: dmd-release druntime-release phobos-release apidocs-release
docs-prerelease: dmd-prerelease druntime-prerelease phobos-prerelease apidocs-prerelease

docs : docs-release docs-prerelease

html : $(ALL_FILES)

verbatim : $(addprefix $(DOC_OUTPUT_DIR)/, $(addsuffix .verbatim,$(PAGES_ROOT))) phobos-prerelease-verbatim

kindle : ${DOC_OUTPUT_DIR}/dlangspec.mobi

pdf : ${DOC_OUTPUT_DIR}/dlangspec.pdf

$(DOC_OUTPUT_DIR)/sitemap.html : $(ALL_FILES_BUT_SITEMAP) $(DMD)
	cp -f sitemap-template.dd $G/sitemap.dd
	(true $(foreach F, $(TARGETS), \
	  && echo \
	    "$F	`sed -n 's/<title>\(.*\) - D Programming Language.*<\/title>/\1/'p $(DOC_OUTPUT_DIR)/$F`")) \
	  | sort --ignore-case --key=2 | sed 's/^\([^	]*\)	\([^\n\r]*\)/<a href="\1">\2<\/a><br>/' >> $G/sitemap.dd
	$(DMD) -conf= -c -o- -Df$@ $(DDOC) $G/sitemap.dd
	rm $G/sitemap.dd

${GENERATED}/${LATEST}.ddoc :
	mkdir -p $(dir $@)
	echo "LATEST=${LATEST}" >$@

${GENERATED}/modlist-${LATEST}.ddoc : modlist.d ${STABLE_DMD} $(DRUNTIME_LATEST_DIR) $(PHOBOS_LATEST_DIR) $(DMD_LATEST_DIR)
	mkdir -p $(dir $@)
	$(STABLE_RDMD) modlist.d $(DRUNTIME_LATEST_DIR) $(PHOBOS_LATEST_DIR) $(DMD_LATEST_DIR) $(MOD_EXCLUDES_RELEASE) \
		$(addprefix --dump , object std etc core $(DMD_SRC_NAME)) >$@

${GENERATED}/modlist-prerelease.ddoc : modlist.d ${STABLE_DMD} $(DRUNTIME_DIR) $(PHOBOS_DIR)
	mkdir -p $(dir $@)
	$(STABLE_RDMD) modlist.d $(DRUNTIME_DIR) $(PHOBOS_DIR) $(DMD_DIR) $(MOD_EXCLUDES_PRERELEASE) \
		$(addprefix --dump , object std etc core $(DMD_SRC_NAME)) >$@

# Run "make -j rebase" for rebasing all dox in parallel!
rebase: rebase-dlang rebase-dmd rebase-druntime rebase-phobos
rebase-dlang: ; $(call REBASE,dlang.org)
rebase-dmd: ; cd $(DMD_DIR) && $(call REBASE,dmd)
rebase-druntime: ; cd $(DRUNTIME_DIR) && $(call REBASE,druntime)
rebase-phobos: ; cd $(PHOBOS_DIR) && $(call REBASE,phobos)

clean:
	rm -rf $(DOC_OUTPUT_DIR) ${GENERATED} dpl-docs/.dub
	rm -rf auto dlangspec-consolidated.d $(addprefix dlangspec,.aux .d .dvi .fdb_latexmk .fls .log .out .pdf .tex .txt .verbatim.txt)
	rm -f docs.json docs-prerelease.json dpl-docs/dpl-docs
	@echo You should issue manually: rm -rf ${DMD_LATEST_DIR} ${DRUNTIME_LATEST_DIR} ${PHOBOS_LATEST_DIR} ${STABLE_DMD_ROOT}

RSYNC_FILTER=-f 'P /Usage' -f 'P /.dpl_rewrite*' -f 'P /install.sh*'

rsync : all kindle pdf
	rsync -avzO --chmod=u=rwX,g=rwX,o=rX --delete $(RSYNC_FILTER) $(DOC_OUTPUT_DIR)/ $(REMOTE_DIR)/

rsync-only :
	rsync -avzO --chmod=u=rwX,g=rwX,o=rX --delete $(RSYNC_FILTER) $(DOC_OUTPUT_DIR)/ $(REMOTE_DIR)/

################################################################################
# Pattern rulez
################################################################################

# NOTE: Depending on the version of make, order matters here. Therefore, put
# sub-directories before their parents.

$(DOC_OUTPUT_DIR)/changelog/%.html : changelog/%_pre.dd $(CHANGELOG_PRE_DDOC) $(DMD)
	$(DMD) -conf= -c -o- -Df$@ $(CHANGELOG_PRE_DDOC) $<

$(DOC_OUTPUT_DIR)/changelog/%.html : changelog/%.dd $(CHANGELOG_DDOC) $(DMD)
	$(DMD) -conf= -c -o- -Df$@ $(CHANGELOG_DDOC) $<

$(DOC_OUTPUT_DIR)/spec/%.html : spec/%.dd $(SPEC_DDOC) $(DMD)
	$(DMD) -c -o- -Df$@ $(SPEC_DDOC) $<

$(DOC_OUTPUT_DIR)/404.html : 404.dd $(DDOC) $(DMD)
	$(DMD) -conf= -c -o- -Df$@ $(DDOC) errorpage.ddoc $<

$(DOC_OUTPUT_DIR)/%.html : %.dd $(DDOC) $(DMD)
	$(DMD) -conf= -c -o- -Df$@ $(DDOC) $<

$(DOC_OUTPUT_DIR)/%.verbatim : %_pre.dd verbatim.ddoc $(DMD)
	$(DMD) -c -o- -Df$@ verbatim.ddoc $<

$(DOC_OUTPUT_DIR)/%.verbatim : %.dd verbatim.ddoc $(DMD)
	$(DMD) -c -o- -Df$@ verbatim.ddoc $<

$(DOC_OUTPUT_DIR)/%.php : %.php.dd $(DDOC) $(DMD)
	$(DMD) -conf= -c -o- -Df$@ $(DDOC) $<

$(DOC_OUTPUT_DIR)/css/% : css/%
	@mkdir -p $(dir $@)
ifeq (1,$(CSS_MINIFY))
	curl -X POST -fsS --data-urlencode 'input@$<' http://cssminifier.com/raw >$@
else
	cp $< $@
endif

$(DOC_OUTPUT_DIR)/%.css : %.css.dd $(DMD)
	$(DMD) -c -o- -Df$@ $<

$(DOC_OUTPUT_DIR)/% : %
	@mkdir -p $(dir $@)
	cp $< $@

$(DOC_OUTPUT_DIR)/dmd-%.html : %.ddoc dcompiler.dd $(DDOC) $(DMD)
	$(DMD) -conf= -c -o- -Df$@ $(DDOC) dcompiler.dd $<

$(DOC_OUTPUT_DIR)/dmd-%.verbatim : %.ddoc dcompiler.dd verbatim.ddoc $(DMD)
	$(DMD) -c -o- -Df$@ verbatim.ddoc dcompiler.dd $<

################################################################################
# Ebook
################################################################################

dlangspec.d : $(SPEC_DD) ${STABLE_DMD}
	$(STABLE_RDMD) ../tools/catdoc.d -o$@ $(SPEC_DD)

dlangspec.html : $(DDOC) ebook.ddoc dlangspec.d $(DMD)
	$(DMD) -conf= $(DDOC) ebook.ddoc dlangspec.d

dlangspec.zip : dlangspec.html ebook.css
	rm -f $@
	zip $@ dlangspec.html ebook.css

$(DOC_OUTPUT_DIR)/dlangspec.mobi : \
		dlangspec.opf dlangspec.html dlangspec.png dlangspec.ncx ebook.css
	rm -f $@ dlangspec.mobi
# kindlegen has warnings, ignore them for now
	-kindlegen dlangspec.opf
	mv dlangspec.mobi $@

################################################################################
# LaTeX
################################################################################

dlangspec-consolidated.d : $(SPEC_DD) ${STABLE_DMD}
	$(STABLE_RDMD) --force ../tools/catdoc.d -o$@ $(SPEC_DD)

dlangspec.tex : $(DMD) $(DDOC) latex.ddoc dlangspec-consolidated.d
	$(DMD) -conf= -Df$@ $(DDOC) latex.ddoc dlangspec-consolidated.d

# Run twice to fix multipage tables and \ref uses
$(DOC_OUTPUT_DIR)/dlangspec.pdf : dlangspec.tex
	mkdir -p .tmp
	pdflatex -draftmode $^
	pdflatex -output-directory=.tmp $^
	mv .tmp/dlangspec.pdf $@
	rm -rf .tmp

################################################################################
# Plaintext/verbatim generation - not part of the build, demo purposes only
################################################################################

dlangspec.txt : $(DMD) macros.ddoc plaintext.ddoc dlangspec-consolidated.d
	$(DMD) -conf= -Df$@ macros.ddoc plaintext.ddoc dlangspec-consolidated.d

dlangspec.verbatim.txt : $(DMD) verbatim.ddoc dlangspec-consolidated.d
	$(DMD) -conf= -Df$@ verbatim.ddoc dlangspec-consolidated.d

################################################################################
# Fetch the latest article from the official D blog
################################################################################

$G/dblog_latest.ddoc:
	@echo "Receiving the latest DBlog article. Disable with DIFFABLE=1"
	curl -s --retry 3 --retry-delay 5 http://blog.dlang.org | grep -m1 'entry-title' | \
		sed -E 's/^.*<a href="(.+)" rel="bookmark">([^<]+)<\/a>.*<time.*datetime="[^"]+">([^<]*)<\/time>.*Author *<\/span><a [^>]+>([^<]+)<\/a>.*/DBLOG_LATEST_TITLE=\2|DBLOG_LATEST_LINK=\1|DBLOG_LATEST_DATE=\3|DBLOG_LATEST_AUTHOR=\4/' | \
		tr '|' '\n' > $@

$G/twid_latest.ddoc:
	@echo "Receiving the latest TWID article. Disable with DIFFABLE=1"
	curl -s --retry 3 --retry-delay 5 http://arsdnet.net/this-week-in-d/twid_latest.dd > $@

################################################################################
# Git rules
################################################################################

../%-${LATEST} :
	git clone -b v${LATEST} --depth=1 ${GIT_HOME}/$(notdir $*) $@

${DMD_DIR} ${DRUNTIME_DIR} ${PHOBOS_DIR} ${TOOLS_DIR} ${INSTALLER_DIR}:
	git clone --depth=1 ${GIT_HOME}/$(notdir $(@F)) $@

################################################################################
# dmd compiler, latest released build and current build
################################################################################

$(DMD) : ${DMD_DIR}
	${MAKE} --directory=${DMD_DIR}/src -f posix.mak AUTO_BOOTSTRAP=1

$(DMD_LATEST) : ${DMD_LATEST_DIR}
	${MAKE} --directory=${DMD_LATEST_DIR}/src -f posix.mak AUTO_BOOTSTRAP=1

dmd-release : $(STD_DDOC) $(DMD_LATEST_DIR) $(DMD_LATEST)
	$(MAKE) AUTO_BOOTSTRAP=1 --directory=$(DMD_LATEST_DIR) -f posix.mak html $(DDOC_VARS_LATEST_HTML)

dmd-prerelease : $(STD_DDOC_PRE) $(DMD_DIR) $(DMD)
	$(MAKE) AUTO_BOOTSTRAP=1 --directory=$(DMD_DIR) -f posix.mak html $(DDOC_VARS_HTML)

dmd-prerelease-verbatim : $(STD_DDOC_PRE) $(DMD_DIR) \
		${DOC_OUTPUT_DIR}/phobos-prerelease/mars.verbatim
${DOC_OUTPUT_DIR}/phobos-prerelease/mars.verbatim: verbatim.ddoc
	mkdir -p $(dir $@)
	$(MAKE) AUTO_BOOTSTRAP=1 --directory=$(DMD_DIR) -f posix.mak html $(DDOC_VARS_VERBATIM)
	$(call CHANGE_SUFFIX,html,verbatim,${DOC_OUTPUT_DIR}/phobos-prerelease-verbatim)
	mv ${DOC_OUTPUT_DIR}/phobos-prerelease-verbatim/* $(dir $@)
	rm -r ${DOC_OUTPUT_DIR}/phobos-prerelease-verbatim

################################################################################
# druntime, latest released build and current build
# TODO: remove DOCDIR and DOCFMT once they have been removed at Druntime
################################################################################

druntime-prerelease : ${DRUNTIME_DIR} $(DMD) $(STD_DDOC_PRE)
	${MAKE} --directory=${DRUNTIME_DIR} -f posix.mak target doc $(DDOC_VARS_HTML) \
		DOCDIR=${DOC_OUTPUT_DIR}/phobos-prerelease \
		DOCFMT="$(addprefix `pwd`/, $(STD_DDOC_PRE))"

druntime-release : ${DRUNTIME_LATEST_DIR} $(DMD_LATEST) $(STD_DDOC)
	${MAKE} --directory=${DRUNTIME_LATEST_DIR} -f posix.mak target doc $(DDOC_VARS_LATEST_HTML) \
	  DOCDIR=${DOC_OUTPUT_DIR}/phobos \
	  DOCFMT="$(addprefix `pwd`/, $(STD_DDOC))"

druntime-prerelease-verbatim : ${DRUNTIME_DIR} \
		${DOC_OUTPUT_DIR}/phobos-prerelease/object.verbatim
${DOC_OUTPUT_DIR}/phobos-prerelease/object.verbatim : $(DMD)
	${MAKE} --directory=${DRUNTIME_DIR} -f posix.mak target doc $(DDOC_VARS_VERBATIM) \
		DOCDIR=${DOC_OUTPUT_DIR}/phobos-prerelease-verbatim \
		DOCFMT="`pwd`/verbatim.ddoc"
	mkdir -p $(dir $@)
	$(call CHANGE_SUFFIX,html,verbatim,${DOC_OUTPUT_DIR}/phobos-prerelease-verbatim)
	mv ${DOC_OUTPUT_DIR}/phobos-prerelease-verbatim/* $(dir $@)
	rm -r ${DOC_OUTPUT_DIR}/phobos-prerelease-verbatim

################################################################################
# phobos, latest released build and current build
################################################################################

.PHONY: phobos-prerelease
phobos-prerelease : ${PHOBOS_FILES_GENERATED} $(STD_DDOC_PRE) druntime-prerelease
	$(MAKE) --directory=$(PHOBOS_DIR_GENERATED) -f posix.mak html $(DDOC_VARS_HTML)

phobos-release : ${PHOBOS_LATEST_FILES_GENERATED} $(DMD_LATEST) $(STD_DDOC) \
		druntime-release dmd-release
	$(MAKE) --directory=$(PHOBOS_LATEST_DIR_GENERATED) -f posix.mak html $(DDOC_VARS_LATEST_HTML)

phobos-prerelease-verbatim : ${PHOBOS_FILES_GENERATED} ${DOC_OUTPUT_DIR}/phobos-prerelease/index.verbatim
${DOC_OUTPUT_DIR}/phobos-prerelease/index.verbatim : verbatim.ddoc \
	    ${DOC_OUTPUT_DIR}/phobos-prerelease/object.verbatim \
	    ${DOC_OUTPUT_DIR}/phobos-prerelease/mars.verbatim
	${MAKE} --directory=${PHOBOS_DIR_GENERATED} -f posix.mak html $(DDOC_VARS_VERBATIM) \
	  DOC_OUTPUT_DIR=${DOC_OUTPUT_DIR}/phobos-prerelease-verbatim
	$(call CHANGE_SUFFIX,html,verbatim,${DOC_OUTPUT_DIR}/phobos-prerelease-verbatim)
	mv ${DOC_OUTPUT_DIR}/phobos-prerelease-verbatim/* $(dir $@)
	rm -r ${DOC_OUTPUT_DIR}/phobos-prerelease-verbatim

################################################################################
# phobos and druntime, latest released build and current build (DDOX version)
################################################################################

apidocs-prerelease : ${DOC_OUTPUT_DIR}/library-prerelease/sitemap.xml ${DOC_OUTPUT_DIR}/library-prerelease/.htaccess
apidocs-release : ${DOC_OUTPUT_DIR}/library/sitemap.xml ${DOC_OUTPUT_DIR}/library/.htaccess
apidocs-serve : $G/docs-prerelease.json
	${DPL_DOCS} serve-html --std-macros=html.ddoc --std-macros=dlang.org.ddoc --std-macros=std.ddoc --std-macros=macros.ddoc --std-macros=std-ddox.ddoc \
	  --override-macros=std-ddox-override.ddoc --package-order=std \
	  --git-target=master --web-file-dir=. $<

${DOC_OUTPUT_DIR}/library-prerelease/sitemap.xml : $G/docs-prerelease.json
	@mkdir -p $(dir $@)
	${DPL_DOCS} generate-html --file-name-style=lowerUnderscored --std-macros=html.ddoc --std-macros=dlang.org.ddoc --std-macros=std.ddoc --std-macros=macros.ddoc --std-macros=std-ddox.ddoc \
	  --override-macros=std-ddox-override.ddoc --package-order=std \
	  --git-target=master $(DPL_DOCS_PATH_RUN_FLAGS) \
		$< ${DOC_OUTPUT_DIR}/library-prerelease

${DOC_OUTPUT_DIR}/library/sitemap.xml : $G/docs.json
	@mkdir -p $(dir $@)
	${DPL_DOCS} generate-html --file-name-style=lowerUnderscored --std-macros=html.ddoc --std-macros=dlang.org.ddoc --std-macros=std.ddoc --std-macros=macros.ddoc --std-macros=std-ddox.ddoc \
	  --override-macros=std-ddox-override.ddoc --package-order=std \
	  --git-target=v${LATEST} $(DPL_DOCS_PATH_RUN_FLAGS) \
	  $< ${DOC_OUTPUT_DIR}/library

${DOC_OUTPUT_DIR}/library/.htaccess : dpl_release_htaccess
	@mkdir -p $(dir $@)
	cp $< $@

${DOC_OUTPUT_DIR}/library-prerelease/.htaccess : dpl_prerelease_htaccess
	@mkdir -p $(dir $@)
	cp $< $@

DMD_EXCLUDE =
ifeq (osx,$(OS))
	DMD_EXCLUDE += -e /scanelf/d -e /libelf/d
else
	DMD_EXCLUDE += -e /scanmach/d -e /libmach/d
endif

$G/docs.json : ${DMD_LATEST} ${DMD_LATEST_DIR} \
			${DRUNTIME_LATEST_DIR} ${PHOBOS_LATEST_FILES_GENERATED} | dpl-docs
	find ${DMD_LATEST_DIR}/src -name '*.d' | \
		sed -e /mscoff/d -e /objc_glue.d/d ${DMD_EXCLUDE}  \
			> $G/.release-files.txt
	find ${DRUNTIME_LATEST_DIR}/src -name '*.d' | \
	  sed -e /unittest.d/d -e /gcstub/d >> $G/.release-files.txt
	find ${PHOBOS_LATEST_DIR_GENERATED} -name '*.d' | \
	  sed -e /unittest.d/d -e /windows/d | sort >> $G/.release-files.txt
	${DMD_LATEST} -J$(DMD_LATEST_DIR)/res -J$(dir $(DMD_LATEST)) -c -o- -version=CoreDdoc \
	  -version=MARS -version=CoreDdoc -version=StdDdoc -Df$G/.release-dummy.html \
	  -Xf$@ -I${PHOBOS_LATEST_DIR_GENERATED} @$G/.release-files.txt
	${DPL_DOCS} filter $@ --min-protection=Protected \
	  --only-documented $(MOD_EXCLUDES_PRERELEASE)
	rm -f $G/.release-files.txt $G/.release-dummy.html

# DDox tries to generate the docs for all `.d` files. However for dmd this is tricky,
# because the `{mach, elf, mscoff}` are platform dependent.
# Thus the need to exclude these files (and the `objc_glue.d` file).
$G/docs-prerelease.json : ${DMD} ${DMD_DIR} ${DRUNTIME_DIR} \
		${PHOBOS_FILES_GENERATED} | dpl-docs
	find ${DMD_DIR}/src -name '*.d' | \
		sed -e /mscoff/d -e /objc_glue.d/d ${DMD_EXCLUDE}  \
			> $G/.prerelease-files.txt
	find ${DRUNTIME_DIR}/src -name '*.d' | sed -e '/gcstub/d' \
	  -e /unittest/d >> $G/.prerelease-files.txt
	find ${PHOBOS_DIR_GENERATED} -name '*.d' | sed -e /unittest.d/d \
	  -e /windows/d | sort >> $G/.prerelease-files.txt
	${DMD} -J$(DMD_DIR)/res -J$(dir $(DMD)) -c -o- -version=MARS -version=CoreDdoc \
	  -version=StdDdoc -Df$G/.prerelease-dummy.html \
	  -Xf$@ -I${PHOBOS_DIR_GENERATED} @$G/.prerelease-files.txt
	${DPL_DOCS} filter $@ --min-protection=Protected \
	  --only-documented $(MOD_EXCLUDES_RELEASE)
	rm -f $G/.prerelease-files.txt $G/.prerelease-dummy.html

################################################################################
# binary targets for DDOX
################################################################################

# workardound Issue 15574
ifneq (osx,$(OS))
    DPL_DOCS_DFLAGS=-conf=$(abspath ${STABLE_DMD_CONF}) -L--no-as-needed
else
    DPL_DOCS_DFLAGS=-conf=$(abspath ${STABLE_DMD_CONF})
endif

.PHONY: dpl-docs
dpl-docs: ${DUB} ${STABLE_DMD}
	DFLAGS="$(DPL_DOCS_DFLAGS)" ${DUB} build --root=${DPL_DOCS_PATH} \
		--compiler=${STABLE_DMD}

${STABLE_DMD_ROOT}/.downloaded:
	mkdir -p ${STABLE_DMD_ROOT}
	TMPFILE=$$(mktemp ${TMP}/dmd-download-deleteme.XXXXXXXX) && curl -fsSL ${STABLE_DMD_URL} > $${TMPFILE}.zip && \
		unzip -qd ${STABLE_DMD_ROOT} $${TMPFILE}.zip && rm $${TMPFILE}.zip
	touch $@

${STABLE_DMD} ${STABLE_RDMD} ${DUB}: ${STABLE_DMD_ROOT}/.downloaded

################################################################################
# chm help files
################################################################################

# testing menu generation
chm-nav.json : $(DDOC) std.ddoc spec/spec.ddoc ${GENERATED}/modlist-${LATEST}.ddoc changelog/changelog.ddoc chm-nav.dd $(DMD)
	$(DMD) -conf= -c -o- -Df$@ $(filter-out $(DMD),$^)
chm-nav-pre.json : $(DDOC) std.ddoc spec/spec.ddoc ${GENERATED}/modlist-prerelease.ddoc changelog/changelog.ddoc chm-nav.dd $(DMD)
	$(DMD) -conf= -c -o- -Df$@ $(filter-out $(DMD),$^)

################################################################################
# Dman tags
################################################################################

d.tag d-tags.json : chmgen.d $(STABLE_DMD) $(ALL_FILES) phobos-release druntime-release
	$(STABLE_RDMD) chmgen.d --root=$(DOC_OUTPUT_DIR) --only-tags

################################################################################
# Assert -> writeln magic
# -----------------------
#
# - This transforms assert(a = b) to writeln(a); // b
# - It creates a copy of Phobos to apply the transformations
# - All "d" files are piped through the transformator,
#   other needed files (e.g. posix.mak) get copied over
################################################################################

ASSERT_WRITELN_BIN = $(GENERATED)/assert_writeln_magic

$(ASSERT_WRITELN_BIN): assert_writeln_magic.d $(DUB) $(STABLE_DMD)
	@mkdir -p $(dir $@)
	$(DUB) build --single --compiler=$(STABLE_DMD) $<
	@mv ./assert_writeln_magic $@

$(ASSERT_WRITELN_BIN)_test: assert_writeln_magic.d $(DUB) $(STABLE_DMD)
	@mkdir -p $(dir $@)
	$(DUB) build --single --compiler=$(STABLE_DMD) --build=unittest $<
	@mv ./assert_writeln_magic $@

$(PHOBOS_FILES_GENERATED): $(PHOBOS_DIR_GENERATED)/%: $(PHOBOS_DIR)/% $(DUB) $(ASSERT_WRITELN_BIN)
	@mkdir -p $(dir $@)
	@if [ $(subst .,, $(suffix $@)) = "d" ] && [ "$@" != "$(PHOBOS_DIR_GENERATED)/index.d" ] ; then \
		$(ASSERT_WRITELN_BIN) -i $< -o $@ ; \
	else cp $< $@ ; fi

$(PHOBOS_LATEST_FILES_GENERATED): $(PHOBOS_LATEST_DIR_GENERATED)/%: $(PHOBOS_LATEST_DIR)/% $(DUB) $(ASSERT_WRITELN_BIN)
	@mkdir -p $(dir $@)
	@if [ $(subst .,, $(suffix $@)) = "d" ] && [ "$@" != "$(PHOBOS_LATEST_DIR_GENERATED)/index.d" ] ; then \
		$(ASSERT_WRITELN_BIN) -i $< -o $@ ; \
	else cp $< $@ ; fi

################################################################################
# Style tests
################################################################################

test: $(ASSERT_WRITELN_BIN)_test all
	@echo "Searching for trailing whitespace"
	@grep -n '[[:blank:]]$$' $$(find . -type f -name "*.dd") ; test $$? -eq 1
	@echo "Searching for undefined macros"
	@grep -n "UNDEFINED MACRO" $$(find $(DOC_OUTPUT_DIR) -type f -name "*.html" -not -path "$(DOC_OUTPUT_DIR)/phobos/*") ; test $$? -eq 1
	@echo "Searching for undefined ddoc"
	@grep -rn '[$$](' $$(find $(DOC_OUTPUT_DIR)/phobos-prerelease -type f -name "*.html") ; test $$? -eq 1
	@echo "Executing assert_writeln_magic tests"
	$<

################################################################################
# Changelog generation
################################################################################

changelog/${NEXT_VERSION}_pre.dd: | ${STABLE_DMD} ../tools ../installer
	$(STABLE_RDMD) $(TOOLS_DIR)/changed.d $(CHANGELOG_VERSION_MASTER) -o $@ \
	--version "${NEXT_VERSION} (upcoming)" --date "To be released" --nightly

changelog/${NEXT_VERSION}.dd: | ${STABLE_DMD} ../tools ../installer
	$(STABLE_RDMD) $(TOOLS_DIR)/changed.d $(CHANGELOG_VERSION_LATEST) -o $@ \
		--version "${NEXT_VERSION}"

pending_changelog: changelog/${NEXT_VERSION}.dd html
	@echo "Please open file:///$(shell pwd)/web/changelog/${NEXT_VERSION}_pre.html in your browser"

.DELETE_ON_ERROR: # GNU Make directive (delete output files on error)
