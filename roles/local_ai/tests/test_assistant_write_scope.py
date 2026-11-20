#!/usr/bin/env python3
"""The assistant's write boundary, which is now code rather than the mount.

Until 2026-11-20 the notes space was mounted read-only with only the campaign
subtree read-write, so the kernel enforced the write scope and this module
would have been testing a belt behind braces. Widening the mount to the whole
space moved that boundary INTO the process, which is exactly when it needs
tests: a mistake in `_writable` is now a mistake that reaches real notes.

Run by CI through the roles/*/tests glob. Offline, no Pi, no model.
"""

import importlib.util
import os
import pathlib
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
AGENT = HERE.parent / "files" / "campaign.py"


def load_agent(space, root="", readonly="Campaigns/Pirate/Templates,Campaigns/Pirate/Rules,.git"):
    """Import the agent fresh with a given scope.

    Its scope comes from the environment at import time, so each case needs
    its own module object rather than a shared one.
    """
    os.environ["CAMPAIGN_SPACE"] = str(space)
    os.environ["CAMPAIGN_ROOT"] = root
    os.environ["CAMPAIGN_READONLY"] = readonly
    os.environ["CAMPAIGN_TRANSCRIPT"] = str(pathlib.Path(space).parent / "transcript.md")
    spec = importlib.util.spec_from_file_location("frey_assistant_under_test", AGENT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class WriteScope(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.space = pathlib.Path(self.tmp.name) / "notes"
        for sub in (
            "Campaigns/Pirate/NPCs",
            "Campaigns/Pirate/Templates",
            "Campaigns/Pirate/Rules",
            "Projects",
        ):
            (self.space / sub).mkdir(parents=True, exist_ok=True)
        (self.space / "index.md").write_text("# index\n")
        self.addCleanup(self.tmp.cleanup)

    def writable(self, agent, rel):
        target, err = agent._safe(rel)
        self.assertIsNone(err, f"_safe refused {rel!r}: {err}")
        return agent._writable(target)

    # --- the whole space is writable, which is the point of the change ------

    def test_page_outside_the_campaign_is_writable(self):
        """The reason for the change: notes that are not the campaign."""
        agent = load_agent(self.space)
        for rel in ("Projects/Van wiring", "index", "Shopping", "a/b/c/deep"):
            ok, why = self.writable(agent, rel)
            self.assertTrue(ok, f"{rel} should be writable, refused: {why}")

    def test_campaign_pages_are_still_writable(self):
        agent = load_agent(self.space)
        ok, why = self.writable(agent, "Campaigns/Pirate/NPCs/Oren Blackwick")
        self.assertTrue(ok, why)

    # --- the reference subtrees are still refused, by this code --------------

    def test_readonly_subtrees_are_refused(self):
        agent = load_agent(self.space)
        for rel in (
            "Campaigns/Pirate/Templates/NPC",
            "Campaigns/Pirate/Rules/Combat",
            "Campaigns/Pirate/Templates/nested/deeper",
        ):
            ok, why = self.writable(agent, rel)
            self.assertFalse(ok, f"{rel} must not be writable")
            self.assertIn("reference material", why)

    def test_readonly_match_is_a_path_prefix_not_a_bare_name(self):
        """A top-level Templates/ is NOT the protected one.

        The old check looked at the first path component relative to the
        campaign root, so moving ROOT to the whole space would have silently
        changed the meaning of "Templates" to a top-level folder and dropped
        the real protection. These two cases pin the distinction.
        """
        agent = load_agent(self.space)
        ok, _ = self.writable(agent, "Templates/something")
        self.assertTrue(ok, "a top-level Templates/ is not the protected subtree")
        ok, _ = self.writable(agent, "Campaigns/Pirate/Templates/something")
        self.assertFalse(ok, "the campaign Templates/ is the protected subtree")

    def test_a_prefix_must_not_match_a_sibling_by_substring(self):
        agent = load_agent(self.space, readonly="Projects")
        ok, _ = self.writable(agent, "Projects/thing")
        self.assertFalse(ok)
        # "ProjectsArchive" merely starts with the same letters.
        ok, why = self.writable(agent, "ProjectsArchive/thing")
        self.assertTrue(ok, f"sibling wrongly refused: {why}")

    # --- escaping the space is still impossible -----------------------------

    def test_traversal_and_absolute_paths_are_refused(self):
        agent = load_agent(self.space)
        for rel in ("../outside", "../../etc/passwd", "Campaigns/../../outside"):
            _, err = agent._safe(rel)
            self.assertIsNotNone(err, f"{rel} should have been refused")
            self.assertIn("escapes", err)

    def test_absolute_path_is_pulled_back_inside(self):
        """A leading slash is stripped rather than honoured."""
        agent = load_agent(self.space)
        target, err = agent._safe("/etc/passwd")
        self.assertIsNone(err)
        self.assertTrue(str(target).startswith(str(self.space.resolve())))

    # --- ROOT still narrows, so the decision is reversible ------------------

    def test_root_narrows_writes_back_to_one_subtree(self):
        agent = load_agent(self.space, root="Campaigns/Pirate")
        ok, _ = self.writable(agent, "Campaigns/Pirate/NPCs/Someone")
        self.assertTrue(ok)
        ok, why = self.writable(agent, "Projects/Van wiring")
        self.assertFalse(ok, "ROOT must still be able to confine writes")
        self.assertIn("Campaigns/Pirate", why)

    # --- the transcript must not land in the notes space --------------------

    def test_transcript_is_outside_the_notes_space(self):
        agent = load_agent(self.space)
        transcript = agent.chat_path().resolve()
        self.assertFalse(
            str(transcript).startswith(str(self.space.resolve()) + os.sep),
            "the transcript must not be a page in the notes space",
        )

    def test_the_git_repo_is_not_writable(self):
        """Git is the undo mechanism; the thing being undone must not edit it.

        .git used to be a separate mount and is now inside the read-write
        space mount, so this protection moved into the readonly list.
        """
        agent = load_agent(self.space)
        ok, why = self.writable(agent, ".git/config")
        self.assertFalse(ok, "the git repo must not be writable")
        self.assertIn("reference material", why)

    def test_default_readonly_is_not_empty(self):
        """An empty default would silently remove the protection entirely."""
        agent = load_agent(self.space)
        self.assertTrue(agent.READONLY_SUBDIRS)


if __name__ == "__main__":
    unittest.main()
