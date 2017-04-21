# Hammer (ham)

Hammer is a tool to manage big projects that consist of
multiple git repositories, which are loosely coupled.

It provides global sync of all managed repositories,
global operations for all or a subset of the repositories,
and integration with Gerrit Code Review.

The outstanding feature is support for consistent changes
in multiple repositories.


## Usage note for CentOS / RHEL

To run ham on CentOS or RHEL, you need to install
`perl-Archive-Zip` and `perl-parent` packages.


## SSH Authentication

ham updates many repositories at once in the background,
typically using ssh as a secure transport. It is
therefore required to use ssh-agent to allow for
non-interactive ssh-authentication.
