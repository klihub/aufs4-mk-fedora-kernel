This script tries to automatically build an AUFS4-enabled version
of your running Fedora kernel. It downloads the fedora kernel source
RPM, tries to patch it with AUFS4 support and rebuilding it. If
successful, the resulting kernel will have the same name/release
as the currently running one with +aufs added. Ditto for the RPM
package names.
