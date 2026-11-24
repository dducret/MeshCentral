# SPDX-License-Identifier: Apache-2.0
"""Portable regression cases for signed-sharing configuration comparison."""
import copy
import unittest

from check_sharing_configuration import check_configuration


class SharingConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.app = {"CFBundleIdentifier": "example.agent", "MeshCentralHostBundleID": "example.agent",
                    "MeshCentralAppGroup": "group.example.agent", "MeshCentralKeychainGroup": "TEST.example.agent"}
        self.extension = dict(self.app, CFBundleIdentifier="example.agent.Broadcast", NSExtension={
            "NSExtensionPointIdentifier": "com.apple.broadcast-services-upload",
            "RPBroadcastProcessMode": "RPBroadcastProcessModeSampleBuffer"})
        self.app_rights = {"com.apple.developer.team-identifier": "TEST", "application-identifier": "TEST.example.agent",
                           "com.apple.security.application-groups": ["group.example.agent"],
                           "keychain-access-groups": ["TEST.example.agent"]}
        self.extension_rights = dict(self.app_rights, **{"application-identifier": "TEST.example.agent.Broadcast"})

    def issues(self):
        return check_configuration(self.app, self.extension, self.app_rights, self.extension_rights)

    def test_matching_signed_configuration(self):
        self.assertEqual(self.issues(), [])

    def test_same_checked_group_but_wrong_plist_value(self):
        self.app["MeshCentralAppGroup"] = self.extension["MeshCentralAppGroup"] = "group.wrong.value"
        issues = self.issues()
        self.assertTrue(any(i.startswith("APP_APP_GROUP_NOT_AUTHORIZED:") for i in issues))
        self.assertTrue(any(i.startswith("EXTENSION_APP_GROUP_NOT_AUTHORIZED:") for i in issues))
        self.assertNotIn("group.wrong.value", "\n".join(issues))

    def test_extension_release_signature_missing_group(self):
        self.extension_rights["com.apple.security.application-groups"] = []
        self.assertTrue(any(i.startswith("EXTENSION_APP_GROUP_NOT_AUTHORIZED:") for i in self.issues()))

    def test_unresolved_build_variable(self):
        self.app["MeshCentralAppGroup"] = "group.$(MESH_HOST_BUNDLE_ID)"
        self.assertTrue(any(i.startswith("APP_APP_GROUP_INVALID:") for i in self.issues()))

    def test_keychain_private_group_does_not_authorize_extension(self):
        del self.extension_rights["keychain-access-groups"]
        self.assertTrue(any(i.startswith("EXTENSION_KEYCHAIN_NOT_AUTHORIZED:") for i in self.issues()))

    def test_app_groups_are_valid_keychain_access_groups(self):
        self.app["MeshCentralKeychainGroup"] = self.extension["MeshCentralKeychainGroup"] = "group.example.agent"
        self.app_rights.pop("keychain-access-groups")
        self.extension_rights.pop("keychain-access-groups")
        self.assertEqual(self.issues(), [])

    def test_extension_identifier_must_match_system_picker(self):
        self.extension["CFBundleIdentifier"] = "example.agent.Other"
        self.assertTrue(any(i.startswith("PICKER_ID_MISMATCH:") for i in self.issues()))

    def test_old_process_mode_nesting_is_rejected(self):
        declaration = self.extension["NSExtension"]
        declaration["NSExtensionAttributes"] = {"RPBroadcastProcessMode": declaration.pop("RPBroadcastProcessMode")}
        self.assertTrue(any(i.startswith("REPLAYKIT_CONFIGURATION:") for i in self.issues()))

    def test_checker_does_not_change_input(self):
        original = copy.deepcopy([self.app, self.extension, self.app_rights, self.extension_rights])
        self.issues()
        self.assertEqual([self.app, self.extension, self.app_rights, self.extension_rights], original)


if __name__ == "__main__":
    unittest.main()
