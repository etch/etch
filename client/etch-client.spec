Name: etch-client
Summary: Etch client
Version: 1.1
Release: 1
Group: Applications/System
License: MIT
buildarch: noarch
Requires: ruby, facter, rcs, crontabs
BuildRoot: %{_builddir}/%{name}-buildroot
%description
Etch client

%files
%defattr(-,root,root)
/usr/sbin/etch
/usr/lib/ruby/site_ruby/1.8/etch.rb
/etc/etch
/usr/sbin/etch_cron_wrapper
/etc/cron.d/etch

