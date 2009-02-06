# When updating the version number you currently need to update
# etch-client.spec, control and pkginfo as well
VER=1.1

all:

redhat: rpmbuild-redhat rpm
rpmbuild-redhat:
	rpm --quiet -q rpm-build || yum -y install rpm-build
BUILDROOT=/var/tmp/etch-client-buildroot
TMPSPEC = etch-client-temp.spec
rpm: etch-client.spec
	#
	# Create package file structure in build root
	#
	rm -rf $(BUILDROOT)
	mkdir -p $(BUILDROOT)/usr/sbin
	cp -p etch $(BUILDROOT)/usr/sbin
	chmod 555 $(BUILDROOT)/usr/sbin/etch
	mkdir -p $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8
	cp -p etch.rb $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8
	chmod 444 $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8/etch.rb
	mkdir -p $(BUILDROOT)/etc/etch
	cp -p ca.pem $(BUILDROOT)/etc/etch
	# Cron job
	mkdir -p $(BUILDROOT)/etc/cron.d
	cp etch_cron $(BUILDROOT)/etc/cron.d/etch
	cp etch_cron_wrapper $(BUILDROOT)/usr/sbin
	chmod 555 $(BUILDROOT)/usr/sbin/etch_cron_wrapper
	#
	# Now build the package
	#
	rpmbuild -bb --buildroot $(BUILDROOT) etch-client.spec
	rm -rf $(BUILDROOT)

debian: control
	rm -rf debtmp
	mkdir -p debtmp/DEBIAN
	grep -v '^#' control > debtmp/DEBIAN/control
	mkdir -p debtmp/usr/sbin
	cp -p etch debtmp/usr/sbin
	chmod 555 debtmp/usr/sbin/etch
	mkdir -p debtmp/usr/lib/ruby/site_ruby/1.8
	cp -p etch.rb debtmp/usr/lib/ruby/site_ruby/1.8
	chmod 444 debtmp/usr/lib/ruby/site_ruby/1.8
	mkdir -p debtmp/etc/etch
	cp -p ca.pem debtmp/etc/etch
	sudo chown -R 0:0 debtmp
	dpkg --build debtmp etch-client-$(VER).deb
	rm -rf debtmp

solaris: pkginfo depend
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
	mkdir -p $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8
	cp -p etch.rb $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8
	chmod 444 $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/etch.rb
	mkdir -p $(BUILDROOT)/etc/etch
	cp -p ca.pem $(BUILDROOT)/etc/etch
	# Cron job for registration
	cat etch_cron_wrapper | sed 's,/usr/bin/perl,/opt/csw/bin/perl,' > $(BUILDROOT)/usr/sbin/etch_cron_wrapper
	chmod 555 $(BUILDROOT)/usr/sbin/etch_cron_wrapper
	#
	# Now build the package
	#
	echo "i pkginfo=./pkginfo" > prototype
	echo "i depend=./depend" >> prototype
	echo "i postinstall=./postinstall" >> prototype
	echo "i postremove=./postremove" >> prototype
	# The tail +2 removes the first line, which is the base directory
	# and doesn't need to be included in the package.
	# The first sed just cleans up the directory names
	# The second sed tell pkgadd to not force our permissions on directories
	#  The $$ in that sed escapes the $ from make
	find $(BUILDROOT) | pkgproto | tail +2 | sed "s,$(BUILDROOT),," | sed '/^d/s/[^ ]* [^ ]* [^ ]*$$/? ? ?/' >> prototype
	pkgmk -r $(BUILDROOT) -d $(PWD)
	pkgtrans . YPCetch-$(VER).pkg YPCetch
	rm -rf YPCetch
	rm -rf $(BUILDROOT)
	rm -f prototype

# On Sparc systems we're having problems with the CSW/Blastwave ruby
# core dumping when running etch.  The Sunfreeware ruby seems to work.
# Sunfreeware doesn't play well with pkg-get, so we create a bit of a
# hybrid.  We still express all the dependencies against CSW, and put
# our library file (etch.rb) into /opt/csw.  We modify etch to use
# the Sunfreeware ruby in /usr/local/bin, but then tell it to also look
# in the /opt/csw directory for libraries.
solaris-sparc: pkginfo depend
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
	mkdir -p $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8
	cp -p etch.rb $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8
	chmod 444 $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/etch.rb
	mkdir -p $(BUILDROOT)/etc/etch
	cp -p ca.pem $(BUILDROOT)/etc/etch
	# Cron job for registration
	cat etch_cron_wrapper | sed 's,/usr/bin/perl,/opt/csw/bin/perl,' > $(BUILDROOT)/usr/sbin/etch_cron_wrapper
	chmod 555 $(BUILDROOT)/usr/sbin/etch_cron_wrapper
	#
	# Now build the package
	#
	echo "i pkginfo=./pkginfo" > prototype
	echo "i depend=./depend" >> prototype
	echo "i postinstall=./postinstall" >> prototype
	echo "i postremove=./postremove" >> prototype
	# The tail +2 removes the first line, which is the base directory
	# and doesn't need to be included in the package.
	# The first sed just cleans up the directory names
	# The second sed tell pkgadd to not force our permissions on directories
	#  The $$ in that sed escapes the $ from make
	find $(BUILDROOT) | pkgproto | tail +2 | sed "s,$(BUILDROOT),," | sed '/^d/s/[^ ]* [^ ]* [^ ]*$$/? ? ?/' >> prototype
	pkgmk -r $(BUILDROOT) -d $(PWD)
	pkgtrans . YPCetch-$(VER)-sparc.pkg YPCetch
	rm -rf YPCetch
	rm -rf $(BUILDROOT)
	rm -f prototype

