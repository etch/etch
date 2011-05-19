Name:		etch
Version:	%VER%
Release:	1%{?dist}
BuildArch:	noarch
Summary:	A tool for system configuration management
Group:		Applications/System
License:	MIT
URL:		http://etch.sourceforge.net/
Source0:	http://downloads.sourceforge.net/project/etch/etch/%{version}/etch-%{version}.tar.gz
BuildRoot:	%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

BuildRequires:	rubygem-rake
Requires:	ruby(abi) = 1.8, facter, cpio

# Per http://fedoraproject.org/wiki/Packaging:Ruby
%{!?ruby_sitelib: %global ruby_sitelib %(ruby -rrbconfig -e 'puts Config::CONFIG["sitelibdir"] ')}

%description
A tool for system configuration management, i.e. management of the
configuration files of the operating system and core applications. Easy for a
professional system administrator to start using, yet scalable to large
and/or complex environments.

%prep
%setup -q

%build

%install
rm -rf %{buildroot}
cd client && rake install[%{buildroot}]

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
%{_sbindir}/*
%{ruby_sitelib}/*
%{_mandir}/man8/*
%config(noreplace) %{_sysconfdir}/*

%changelog

