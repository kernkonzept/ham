# Hammer (ham)

Hammer is a tool to manage big projects that consist of
multiple git repositories, which are loosely coupled.

It provides global sync of all managed repositories,
global operations for all or a subset of the repositories,
and integration with Gerrit Code Review.

The outstanding feature is support for consistent changes
in multiple repositories.


## Dependencies

On Debian-based systems, install:

    $ apt-get install libgit-repository-perl libxml-mini-perl liburi-perl

On RPM-based systems such as Fedora or RHEL you need to install:

    $ dnf install perl-Git-Repository-Plugin-AUTOLOAD perl-URI perl-CPAN perl-Test perl-File-pushd
    $ cpan install XML::Mini::Document

On Arch Linux, these packages need to be installed from the AUR by a method of your choice:

    $ yay -S perl-git-repository perl-xml-mini perl-uri

## SSH Authentication

ham updates many repositories at once in the background,
typically using ssh as a secure transport. It is
therefore required to use ssh-agent to allow for
non-interactive ssh-authentication.
