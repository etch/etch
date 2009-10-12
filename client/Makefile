BUILDROOT=/var/tmp/etch-client-buildroot
# Grab the current version from the library
VER=$(shell ruby -e "$$:.unshift('.'); require 'etchclient'; puts Etch::Client::VERSION")

all:

redhat: redhatprep rpm
redhatprep:
	# Install everything needed for the command which sets VER above
	rpm --quiet -q ruby || sudo yum install ruby
	# And the package which contains the rpmbuild command
	rpm --quiet -q rpm-build || sudo yum install rpm-build
TMPSPEC = etch-client-temp.spec
rpm: etch-client.spec
	#
	# Create package file structure in build root
	#
	rm -rf $(BUILDROOT)
	mkdir -p $(BUILDROOT)/usr/sbin
	cp -p etch $(BUILDROOT)/usr/sbin
	chmod 555 $(BUILDROOT)/usr/sbin/etch
	cp -p etch_to_trunk $(BUILDROOT)/usr/sbin
	chmod 555 $(BUILDROOT)/usr/sbin/etch_to_trunk
	mkdir -p $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8
	cp -p etchclient.rb $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8
	chmod 444 $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8/etchclient.rb
	cp -p ../server/lib/etch.rb $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8
	chmod 444 $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8/etch.rb
	cp -p ../server/lib/versiontype.rb $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8
	chmod 444 $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8/versiontype.rb
	mkdir -p $(BUILDROOT)/usr/share/man/man8
	cp -p etch.8 $(BUILDROOT)/usr/share/man/man8
	mkdir -p $(BUILDROOT)/etc/etch
	cp -p ca.pem $(BUILDROOT)/etc/etch
	cp -p dhparams $(BUILDROOT)/etc/etch
	# Cron job
	mkdir -p $(BUILDROOT)/etc/cron.d
	cp etch_cron $(BUILDROOT)/etc/cron.d/etch
	cp etch_cron_wrapper $(BUILDROOT)/usr/sbin
	chmod 555 $(BUILDROOT)/usr/sbin/etch_cron_wrapper
	#
	# Now build the package
	#
	sed 's/VER/$(VER)/' etch-client.spec > etch-client.spec_withversion
	rpmbuild -bb --buildroot $(BUILDROOT) etch-client.spec_withversion
	rm -rf $(BUILDROOT)

debian: debianprep deb
debianprep:
	# Install everything needed for the command which sets VER above
	sudo apt-get --no-upgrade --quiet install ruby libopenssl-ruby rubygems facter
deb: control
	rm -rf $(BUILDROOT)
	mkdir -p $(BUILDROOT)/DEBIAN
	grep -v '^#' control | sed 's/VER/$(VER)/' > $(BUILDROOT)/DEBIAN/control
	mkdir -p $(BUILDROOT)/usr/sbin
	cp -p etch $(BUILDROOT)/usr/sbin
	chmod 555 $(BUILDROOT)/usr/sbin/etch
	cp -p etch_to_trunk $(BUILDROOT)/usr/sbin
	chmod 555 $(BUILDROOT)/usr/sbin/etch_to_trunk
	mkdir -p $(BUILDROOT)/usr/local/lib/site_ruby/1.8
	cp -p etchclient.rb $(BUILDROOT)/usr/local/lib/site_ruby/1.8
	chmod 444 $(BUILDROOT)/usr/local/lib/site_ruby/1.8/etchclient.rb
	cp -p ../server/lib/etch.rb $(BUILDROOT)/usr/local/lib/site_ruby/1.8
	chmod 444 $(BUILDROOT)/usr/local/lib/site_ruby/1.8/etch.rb
	cp -p ../server/lib/versiontype.rb $(BUILDROOT)/usr/local/lib/site_ruby/1.8
	chmod 444 $(BUILDROOT)/usr/local/lib/site_ruby/1.8/versiontype.rb
	mkdir -p $(BUILDROOT)/usr/share/man/man8
	cp -p etch.8 $(BUILDROOT)/usr/share/man/man8
	mkdir -p $(BUILDROOT)/etc/etch
	cp -p ca.pem $(BUILDROOT)/etc/etch
	cp -p dhparams $(BUILDROOT)/etc/etch
	sudo chown -R 0:0 $(BUILDROOT)
	dpkg --build $(BUILDROOT) etch-client-$(VER).deb
	rm -rf $(BUILDROOT)

solaris: solarisprep sysvpkg sysvpkg-sparc
solarisprep:
	# Install everything needed for the command which sets VER above
	pkginfo -q CSWruby || sudo pkg-get -i ruby
	pkginfo -q CSWrubygems || sudo pkg-get -i rubygems
	pkginfo -q CSWfacter || sudo pkg-get -i facter
sysvpkg: pkginfo depend
	#
	# Create package file structure in build root
	#
	rm -rf $(BUILDROOT)
	mkdir -p $(BUILDROOT)/usr/sbin
	cp -p etch $(BUILDROOT)/usr/sbin
	mv $(BUILDROOT)/usr/sbin/etch $(BUILDROOT)/usr/sbin/etch.tmp
	cat $(BUILDROOT)/usr/sbin/etch.tmp | sed 's,/usr/bin/ruby,/opt/csw/bin/ruby,' > $(BUILDROOT)/usr/sbin/etch
	rm $(BUILDROOT)/usr/sbin/etch.tmp
	chmod 555 $(BUILDROOT)/usr/sbin/etch
	cp -p etch_to_trunk $(BUILDROOT)/usr/sbin
	mv $(BUILDROOT)/usr/sbin/etch_to_trunk $(BUILDROOT)/usr/sbin/etch_to_trunk.tmp
	cat $(BUILDROOT)/usr/sbin/etch_to_trunk.tmp | sed 's,/usr/bin/ruby,/opt/csw/bin/ruby,' > $(BUILDROOT)/usr/sbin/etch_to_trunk
	rm $(BUILDROOT)/usr/sbin/etch_to_trunk.tmp
	chmod 555 $(BUILDROOT)/usr/sbin/etch_to_trunk
	mkdir -p $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8
	cp -p etchclient.rb $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8
	chmod 444 $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/etchclient.rb
	cp -p ../server/lib/etch.rb $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8
	chmod 444 $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/etch.rb
	cp -p ../server/lib/versiontype.rb $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8
	chmod 444 $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/versiontype.rb
	mkdir -p $(BUILDROOT)/usr/share/man/man8
	cp -p etch.8 $(BUILDROOT)/usr/share/man/man8
	mkdir -p $(BUILDROOT)/etc/etch
	cp -p ca.pem $(BUILDROOT)/etc/etch
	cp -p dhparams $(BUILDROOT)/etc/etch
	# Cron job for registration
	cat etch_cron_wrapper | sed 's,/usr/bin/perl,/opt/csw/bin/perl,' > $(BUILDROOT)/usr/sbin/etch_cron_wrapper
	chmod 555 $(BUILDROOT)/usr/sbin/etch_cron_wrapper
	#
	# Now build the package
	#
	rm -rf solbuild
	mkdir solbuild
	sed 's/%VER%/$(VER)/' pkginfo > solbuild/pkginfo
	echo "i pkginfo=./pkginfo" > solbuild/prototype
	cp depend solbuild/depend
	echo "i depend=./depend" >> solbuild/prototype
	cp postinstall solbuild/postinstall
	echo "i postinstall=./postinstall" >> solbuild/prototype
	cp postremove solbuild/postremove
	echo "i postremove=./postremove" >> solbuild/prototype
	# The tail +2 removes the first line, which is the base directory
	# and doesn't need to be included in the package.
	# The first sed just cleans up the directory names
	# The second sed tell pkgadd to not force our permissions on directories
	#  The $$ in that sed escapes the $ from make
	find $(BUILDROOT) | pkgproto | tail +2 | sed "s,$(BUILDROOT),," | sed '/^d/s/[^ ]* [^ ]* [^ ]*$$/? ? ?/' >> solbuild/prototype
	cd solbuild && pkgmk -r $(BUILDROOT) -d $(PWD)/solbuild
	pkgtrans solbuild ../YPCetch-$(VER).pkg YPCetch
	rm -rf solbuild
	rm -rf $(BUILDROOT)

# On Sparc systems we're having problems with the CSW/Blastwave ruby
# core dumping when running etch.  The Sunfreeware ruby seems to work.
# Sunfreeware doesn't play well with pkg-get, so we create a bit of a
# hybrid.  We still express all the dependencies against CSW, and put
# our library file (etchclient.rb) into /opt/csw.  We modify etch to use
# the Sunfreeware ruby in /usr/local/bin, but then tell it to also look
# in the /opt/csw directory for libraries.
# I'm going to guess that the smaller utilities like etch_to_trunk won't have
# problems, so I'm leaving them set to /opt/csw/bin/ruby.
sysvpkg-sparc: pkginfo depend
	#
	# Create package file structure in build root
	#
	rm -rf $(BUILDROOT)
	mkdir -p $(BUILDROOT)/usr/sbin
	cp -p etch $(BUILDROOT)/usr/sbin
	mv $(BUILDROOT)/usr/sbin/etch $(BUILDROOT)/usr/sbin/etch.tmp
	cat $(BUILDROOT)/usr/sbin/etch.tmp | sed 's,/usr/bin/ruby,/usr/local/bin/ruby,' > $(BUILDROOT)/usr/sbin/etch
	rm $(BUILDROOT)/usr/sbin/etch.tmp
	mv $(BUILDROOT)/usr/sbin/etch $(BUILDROOT)/usr/sbin/etch.tmp
	#  The $$ in that awk escapes the $ from make
	cat $(BUILDROOT)/usr/sbin/etch.tmp | awk '/unshift.*__FILE__/ {print "$$:.unshift \"/opt/csw/lib/ruby/site_ruby/1.8\"\n" $$0; next}; {print}' > $(BUILDROOT)/usr/sbin/etch
	rm $(BUILDROOT)/usr/sbin/etch.tmp
	chmod 555 $(BUILDROOT)/usr/sbin/etch
	cp -p etch_to_trunk $(BUILDROOT)/usr/sbin
	mv $(BUILDROOT)/usr/sbin/etch_to_trunk $(BUILDROOT)/usr/sbin/etch_to_trunk.tmp
	cat $(BUILDROOT)/usr/sbin/etch_to_trunk.tmp | sed 's,/usr/bin/ruby,/opt/csw/bin/ruby,' > $(BUILDROOT)/usr/sbin/etch_to_trunk
	rm $(BUILDROOT)/usr/sbin/etch_to_trunk.tmp
	chmod 555 $(BUILDROOT)/usr/sbin/etch_to_trunk
	mkdir -p $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8
	cp -p etchclient.rb $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8
	chmod 444 $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/etchclient.rb
	cp -p ../server/lib/etch.rb $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8
	chmod 444 $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/etch.rb
	cp -p ../server/lib/versiontype.rb $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8
	chmod 444 $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/versiontype.rb
	mkdir -p $(BUILDROOT)/usr/share/man/man8
	cp -p etch.8 $(BUILDROOT)/usr/share/man/man8
	mkdir -p $(BUILDROOT)/etc/etch
	cp -p ca.pem $(BUILDROOT)/etc/etch
	cp -p dhparams $(BUILDROOT)/etc/etch
	# Cron job for registration
	cat etch_cron_wrapper | sed 's,/usr/bin/perl,/opt/csw/bin/perl,' > $(BUILDROOT)/usr/sbin/etch_cron_wrapper
	chmod 555 $(BUILDROOT)/usr/sbin/etch_cron_wrapper
	#
	# Now build the package
	#
	rm -rf solbuild
	mkdir solbuild
	sed 's/%VER%/$(VER)/' pkginfo > solbuild/pkginfo
	echo "i pkginfo=./pkginfo" > solbuild/prototype
	cp depend solbuild/depend
	echo "i depend=./depend" >> solbuild/prototype
	cp postinstall solbuild/postinstall
	echo "i postinstall=./postinstall" >> solbuild/prototype
	cp postremove solbuild/postremove
	echo "i postremove=./postremove" >> solbuild/prototype
	# The tail +2 removes the first line, which is the base directory
	# and doesn't need to be included in the package.
	# The first sed just cleans up the directory names
	# The second sed tell pkgadd to not force our permissions on directories
	#  The $$ in that sed escapes the $ from make
	find $(BUILDROOT) | pkgproto | tail +2 | sed "s,$(BUILDROOT),," | sed '/^d/s/[^ ]* [^ ]* [^ ]*$$/? ? ?/' >> solbuild/prototype
	cd solbuild && pkgmk -r $(BUILDROOT) -d $(PWD)/solbuild
	pkgtrans solbuild ../YPCetch-$(VER)-sparc.pkg YPCetch
	rm -rf solbuild
	rm -rf $(BUILDROOT)

