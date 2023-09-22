#!/bin/bash
# This script verifies Firefox is installed in the right way. Firefox is used
# to set the GitHub SSH keys and GitHub personal access tokens automatically.
# And to control a Firefox browser, it needs to be installed using apt instead
# of snap. https://stackoverflow.com/questions/72405117
# https://www.omgubuntu.co.uk/2022/04/how-to-install-firefox-deb-apt-ubuntu-22-04
# https://askubuntu.com/questions/1399383/

# Run with:
# bash -c "source src/import.sh && src/prerequisites/firefox_version.sh swap_snap_firefox_with_ppa_apt_firefox_installation"

command_output_contains() {
  local substring="$1"
  shift
  # shellcheck disable=SC2124
  local command_output="$@"
  if grep -q "$substring" <<<"$command_output"; then
    #if "$command" | grep -q "$substring"; then
    echo "FOUND"
  else
    echo "NOTFOUND"
  fi
}

#######################################
# Checks if firefox is installed using snap or not.
# Locals:
#  respones_lines
#  found_firefox
# Globals:
#  None
# Arguments:
#  None
# Returns:
#  0 If command was evaluated successfully.
# Outputs:
#  FOUND if firefox is installed using snap.
#  NOTFOUND if firefox is not installed using snap.
#######################################
firefox_via_snap() {
  local respons_lines
  respons_lines="$(snap list)"
  local found_firefox
  found_firefox=$(command_output_contains "firefox" "${respons_lines}")
  echo "$found_firefox"
}

#######################################
# Checks if firefox is installed using ppa and apt or not.
# Locals:
#  respones_lines
#  found_firefox
# Globals:
#  None
# Arguments:
#  None
# Returns:
#  0 If command was evaluated successfully.
# Outputs:
#  FOUND if firefox is installed using ppa and apt.
#  NOTFOUND if firefox is not installed using ppa and apt.
#######################################
firefox_via_apt() {
  local respons_lines
  respons_lines="$(apt list --installed)"
  local found_firefox
  found_firefox=$(command_output_contains "firefox" "${respons_lines}")
  echo "$found_firefox"
}

#######################################
# Checks if firefox is added as ppa or not.
# Locals:
#  respones_lines
#  ppa_indicator
#  found_firefox_ppa
# Globals:
#  None
# Arguments:
#  None
# Returns:
#  0 If command was evaluated successfully.
# Outputs:
#  FOUND if firefox is added as ppa.
#  NOTFOUND if firefox is not added as ppa.
#######################################
firefox_ppa_is_added() {
  # Get list of ppa packages added for apt usage.
  local respons_lines
  respons_lines="$(apt policy)"
  # Specify identifier for firefox ppa presence.
  local ppa_indicator="https://ppa.launchpadcontent.net/mozillateam/ppa/ubuntu"
  local found_firefox_ppa
  found_firefox_ppa=$(command_output_contains "$ppa_indicator" "${respons_lines}")
  echo "$found_firefox_ppa"
}

#######################################
# Remove Firefox if it is installed using snap.
# Locals:
#  respones_lines
#  found_firefox
# Globals:
#  None
# Arguments:
#  None
# Returns:
#  0 If command was evaluated successfully.
# Outputs:
#  FOUND if firefox is installed using snap.
#  NOTFOUND if firefox is not installed using snap.
#######################################
remove_snap_install_firefox_if_existant() {
  if [ "$(firefox_via_snap)" == "FOUND" ]; then

    # Prompt user for permission.
    ask_user_swapping_firefox_install_is_ok

    # User permission is granted here, remove firefox snap installation.
    yes | sudo snap remove firefox 2>&1
    assert_firefox_is_not_installed_using_snap
    echo "2.a Firefox is removed." >/dev/tty
  fi
  assert_firefox_is_not_installed_using_snap
}

#######################################
# Ask user for permission to swap out Firefox installation.
# Locals:
#  yn
# Globals:
#  None
# Arguments:
#  None
# Returns:
#  0 If command was evaluated successfully.
#  3 If the user terminates the program.
# Outputs:
#  Message indicating Firefox will be uninstalled.
#######################################
ask_user_swapping_firefox_install_is_ok() {
  echo "" >/dev/tty
  echo "Hi, firefox is installed using snap. To automatically add your " >/dev/tty
  echo "access tokens to GitHub, we need to control the firefox browser." >/dev/tty
  echo "To control the firefox browser, we need to switch the installation" >/dev/tty
  echo "method from snap to apt." >/dev/tty
  echo "" >/dev/tty
  echo "We will not preserve your bookmarks, history and extensions." >/dev/tty
  echo "" >/dev/tty
  while true; do
    # shellcheck disable=SC2086,SC2162
    read -p "May we proceed? (y/n)? " yn
    case $yn in
    [Yy]*)
      echo "Removing Firefox, please wait 5 minutes, we will tell you when it is done."
      break
      ;;
    [Nn]*)
      echo "Installation terminated by user."
      exit 3
      ;;
    *) echo "Please answer yes or no." >/dev/tty ;;
    esac
  done
}

#######################################
# Asserts Firefox is not installed using snap, throws an error otherwise.
# Locals:
#  None
# Globals:
#  None
# Arguments:
#  None
# Returns:
#  0 If Firefox is not installed using snap.
#  1 If Firefox is still installed using snap.
# Outputs:
#  Nothing
#######################################
# Run with:
assert_firefox_is_not_installed_using_snap() {
  if [ "$(firefox_via_snap)" == "FOUND" ]; then
    echo "Error, Firefox installation was still installed using snap." >/dev/tty
    exit 2
  fi
}
assert_firefox_is_installed_using_ppa() {
  if [ "$(firefox_via_apt)" != "FOUND" ]; then
    echo "Error, Firefox installation was not performed using ppa and apt." >/dev/tty
    exit 2
  fi
}

#######################################
# Asserts Firefox ppa is added to apt.
# Locals:
#  None
# Globals:
#  None
# Arguments:
#  None
# Returns:
#  0 If Firefox ppa is added to apt.
#  4 Otherwise.
# Outputs:
#  Error message indicating firefox ppa is not added correctly.
#######################################
# Run with:
assert_firefox_ppa_is_added_to_apt() {
  if [ "$(firefox_ppa_is_added)" == "NOTFOUND" ]; then
    echo "Error, Firefox ppa was not added to apt." >/dev/tty
    exit 4
  fi
}
assert_firefox_ppa_is_removed_from_apt() {
  if [ "$(firefox_ppa_is_added)" == "FOUND" ]; then
    echo "Error, Firefox ppa was not removed from apt." >/dev/tty
    exit 4
  fi
}

#######################################
# Adds firefox ppa to install using apt if it is not added yet.
# Locals:
#  None
# Globals:
#  None
# Arguments:
#  None
# Returns:
#  0 If Firefox is not installed using snap.
#  1 If Firefox is still installed using snap.
# Outputs:
#  Nothing
#######################################
add_firefox_ppa_if_not_in_yet() {
  if [ "$(firefox_ppa_is_added)" == "NOTFOUND" ]; then
    echo "Now adding Firefox ppa to apt." >/dev/tty
    echo "" >/dev/tty
    yes | sudo add-apt-repository ppa:mozillateam/ppa
  fi
  assert_firefox_ppa_is_added_to_apt
}
remove_firefox_ppa() {
  if [ "$(firefox_ppa_is_added)" == "FOUND" ]; then
    echo "Now removing Firefox ppa to apt." >/dev/tty
    echo "" >/dev/tty
    yes | sudo add-apt-repository --remove ppa:mozillateam/ppa
  fi
  assert_firefox_ppa_is_removed_from_apt
}

#######################################
# Asserts the Firefox installation package preference is set to ppa/apt. Does
# this by verifying the file content is as expected using hardcoded MD5Sum.
# Locals:
#  None
# Globals:
#  None
# Arguments:
#  None
# Returns:
#  0 If Firefox is not installed using snap.
#  1 If Firefox is still installed using snap.
# Outputs:
#  Nothing
#######################################
assert_firefox_installation_package_preference_file_content() {
  local preferences_path="$1"
  local md5_output
  md5_output="$(md5sum "$preferences_path")"
  local expected_md5_output="961023613b10ce4ae8150f78d698a53e  $preferences_path"
  if [ "$md5_output" != "$expected_md5_output" ]; then
    echo "Error, the md5 output of: $preferences_path is not as expected." >/dev/tty
    echo "md5_output=         $md5_output" >/dev/tty
    echo "expected_md5_output=$expected_md5_output" >/dev/tty
    exit 5
  fi
}

assert_firefox_auto_update_file_content() {
  local preferences_path="$1"
  local md5_output
  md5_output="$(md5sum "$preferences_path")"
  local expected_md5_output="ffd6e239ef98a236741f4ba5c84ab20e  $preferences_path"
  if [ "$md5_output" != "$expected_md5_output" ]; then
    echo "Error, the md5 output of: $preferences_path is not as expected." >/dev/tty
    echo "md5_output=         $md5_output" >/dev/tty
    echo "expected_md5_output=$expected_md5_output" >/dev/tty
    exit 5
  fi
}

#######################################
# Sets the Firefox installation package preference from snap to ppa/apt.
# Locals:
#  preferences_path
# Globals:
#  None
# Arguments:
#  None
# Returns:
#  0 If Firefox is not installed using snap.
#  1 If Firefox is still installed using snap.
# Outputs:
#  Nothing
#######################################
# Run with:
change_firefox_package_priority() {
  local preferences_path="/etc/apt/preferences.d/mozilla-firefox"

  # Set the installation package preference in firefox.
  echo 'Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001' | sudo tee "$preferences_path"

  # Verify the installation package preference is set correctly in firefox.
  assert_firefox_installation_package_preference_file_content "$preferences_path"
}

#######################################
# Ensures the firefox installation is updated automatically.
# Locals:
#  update_filepath
# Globals:
#  None
# Arguments:
#  None
# Returns:
#  0 If Firefox is not installed using snap.
#  1 If Firefox is still installed using snap.
# Outputs:
#  Nothing
#######################################
ensure_firefox_is_updated_automatically() {
  local update_filepath="/etc/apt/apt.conf.d/51unattended-upgrades-firefox"
  # Set the installation package preference in firefox.
  # shellcheck disable=SC2154
  # shellcheck disable=SC2016
  echo 'Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:${distro_codename}";' | sudo tee "$update_filepath"

  # Verify the installation package preference is set correctly in firefox.
  assert_firefox_auto_update_file_content "$update_filepath"
}

#######################################
# Installs firefox using ppa and apt.
# Locals:
#  None
# Globals:
#  None
# Arguments:
#  None
# Returns:
#  0 If Firefox is installed using ppa and apt.
#  1 If Firefox is mpt installed using ppa and apt.
# Outputs:
#  Nothing
#######################################
install_firefox_using_ppa() {
  if [ "$(firefox_via_apt)" == "NOTFOUND" ]; then
    yes | sudo apt install firefox 2>&1
  fi
  assert_firefox_is_installed_using_ppa
  echo "Firefox is installed successfully using ppa and apt." >/dev/tty
}

swap_snap_firefox_with_ppa_apt_firefox_installation() {
  # Swap Firefox installation from snap to ppa/apt using functions above.
  # 0. Detect how firefox is installed.
  # 1. If firefox installed with snap:
  # 1.a Ask user for permission to swap out Firefox installation.
  # 1.b Verify and mention the bookmarks, addons and history are not removed.
  # 1.c Remove snap firefox if it exists.
  # 1.d Verify snap firefox is removed.
  remove_snap_install_firefox_if_existant

  # 2.a Add firefox ppa to apt if not yet in.
  # 2.b Verify firefox ppa is added (successfully).
  add_firefox_ppa_if_not_in_yet
  #remove_firefox_ppa

  # 3.a Change Firefox package priority to ensure it is installed from PPA/deb/apt
  # instead of snap.
  # 3.b Verify Firefox installation priority was set correctly.
  change_firefox_package_priority

  # 4.a Ensure the Firefox installation is automatically updated.
  # 4.b Verify the auto update command is completed successfully.
  ensure_firefox_is_updated_automatically

  # 5.a Install Firefox using apt.
  # 5.v Verify firefox is installed successfully, and only once, using apt/PPA.
  install_firefox_using_ppa
}

swap_snap_firefox_with_ppa_apt_firefox_installation
