"""bin/rice-feeds: what each GitHub thread and Gmail message becomes, offline.

Threads are shaped like GET /notifications; the comment / pull request a
thread points at comes from a stub instead of gh.
"""
import importlib.machinery
import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture(scope="module")
def rf():
    loader = importlib.machinery.SourceFileLoader("rice_feeds", str(ROOT / "bin" / "rice-feeds"))
    spec = importlib.util.spec_from_loader("rice_feeds", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    mod._me[:] = ["kitsunekode"]
    return mod


def conf(**over):
    c = {"gmail": "", "gmailQuery": "is:unread", "github": True, "mute": [], "quiet": [], "bots": "quiet"}
    c.update(over)
    return c


def thread(reason, title, kind="PullRequest", repo="KitsuneKode/kunai", number=12, comment=True):
    api = f"https://api.github.com/repos/{repo}"
    url = None if kind == "CheckSuite" else f"{api}/{'pulls' if kind == 'PullRequest' else 'issues'}/{number}"
    return {
        "id": f"{reason}-{number}", "reason": reason, "updated_at": "2026-11-05T00:00:00Z",
        "repository": {"full_name": repo},
        "subject": {"title": title, "type": kind, "url": url,
                    "latest_comment_url": f"{api}/issues/comments/9" if comment and url else url},
    }


def by(login, body="", html=""):
    return lambda url: {"user": {"login": login, "avatar_url": f"https://avatars/{login}"}, "body": body, "html_url": html}


def test_failed_ci_peeks_and_groups_per_branch(rf):
    t = thread("ci_activity", "CI workflow run failed for fix/pointer branch", kind="CheckSuite")
    c = rf.gh_thread(t, fetch=lambda u: pytest.fail("CI needs no lookup"), c=conf())
    assert (c["title"], c["status"], c["tone"]) == ("CI", "Run failed", "critical")
    assert c["peek"] and not c["quiet"]
    assert c["body"] == "kunai · fix/pointer"
    assert c["group"] == "gh:ci:KitsuneKode/kunai:CI:fix/pointer"
    assert c["url"].endswith("actions?query=branch%3Afix/pointer")
    assert c["reply"] is None


def test_ci_on_a_dependabot_branch_is_quiet(rf):
    t = thread("ci_activity", "CI workflow run failed for dependabot/npm_and_yarn/vite-6 branch", kind="CheckSuite")
    c = rf.gh_thread(t, fetch=None, c=conf())
    assert c["quiet"] and not c["peek"]


def test_dependabot_pull_request_is_quiet_and_has_no_reply(rf):
    t = thread("review_requested", "chore(deps): bump vite from 5 to 6")
    c = rf.gh_thread(t, fetch=by("dependabot[bot]"), c=conf())
    assert c["quiet"] and not c["peek"] and c["reply"] is None


def test_a_bot_commenting_on_your_pr_is_quiet(rf):
    t = thread("comment", "feat: island")
    assert rf.gh_thread(t, fetch=by("coderabbitai[bot]", "Walkthrough"), c=conf())["quiet"]


def test_bots_hide_and_show(rf):
    t = thread("review_requested", "chore(deps): bump vite")
    assert rf.gh_thread(t, fetch=by("dependabot[bot]"), c=conf(bots="hide")) is None
    assert not rf.gh_thread(t, fetch=by("dependabot[bot]"), c=conf(bots="show"))["quiet"]


def test_a_mention_peeks_with_who_said_what_and_a_reply(rf):
    t = thread("mention", "Island stutters on resume", kind="Issue", number=40)
    c = rf.gh_thread(t, fetch=by("mia", "@KitsuneKode can you look at **this**?", "https://github.com/x#issuecomment-9"), c=conf())
    assert c["status"] == "Mentioned you" and c["peek"]
    assert c["body"] == "mia: @KitsuneKode can you look at this ?"
    assert c["reply"] == ("KitsuneKode/kunai", "40")
    assert c["url"] == "https://github.com/x#issuecomment-9"
    assert (c["who"], c["avatar"]) == ("mia", "https://avatars/mia")


def test_your_own_comment_is_not_news(rf):
    assert rf.gh_thread(thread("author", "fix: lock"), fetch=by("KitsuneKode", "done"), c=conf()) is None


def test_a_review_request_says_who_asked_not_the_pr_body(rf):
    t = thread("review_requested", "feat: greeter", comment=False)
    c = rf.gh_thread(t, fetch=by("mia", "A very long description"), c=conf())
    assert c["body"] == "kunai #12 · by mia"
    assert c["peek"] and c["reply"] is None


def test_muted_and_quiet_repos(rf):
    t = thread("mention", "hi", repo="someorg/big")
    assert rf.gh_thread(t, fetch=by("mia", "hi"), c=conf(mute=["someorg/*"])) is None
    c = rf.gh_thread(t, fetch=by("mia", "hi"), c=conf(quiet=["someorg/big"]))
    assert c["quiet"] and not c["peek"]


def test_other_owners_keep_their_name(rf):
    c = rf.gh_thread(thread("comment", "x", repo="other/repo"), fetch=by("mia", "hi"), c=conf())
    assert c["body"] == "mia: hi"
    assert rf.short("other/repo") == "other/repo" and rf.short("KitsuneKode/kunai") == "kunai"


MAIL = b"""From: =?utf-8?q?Priya_Shah?= <priya@example.com>
Subject: Offer letter - next steps
Message-ID: <abc@example.com>
References: <first@example.com>

"""
BODY = b"""Content-Type: multipart/alternative; boundary=XX
MIME-Version: 1.0

--XX
Content-Type: text/html; charset=utf-8

<html><head><style>p{color:red}</style></head><body><p>Hi,</p><p>Offer &amp; timeline attached.</p></body></html>
--XX--
"""


def test_mail_card(rf):
    c = rf.mail_card(MAIL, MAIL.rstrip(b"\n") + b"\n" + BODY, "1784")
    assert (c["from"], c["subject"], c["replyTo"]) == ("Priya Shah", "Offer letter - next steps", "priya@example.com")
    assert c["snippet"] == "Hi, Offer & timeline attached."
    assert c["thread"] == "6f8" and c["url"].endswith("#all/6f8")
    assert not c["noreply"]


def test_no_reply_senders_get_no_reply_field(rf):
    for sender in (b"GitHub <noreply@github.com>", b"Bank <do-not-reply@bank.in>", b"x <notifications@linear.app>"):
        assert rf.mail_card(b"From: " + sender + b"\nSubject: hi\n\n")["noreply"]


def test_reply_threads_with_the_original(rf):
    c = rf.mail_card(MAIL)
    msg = rf.reply_message("me@gmail.com", c, "Thanks, will do.")
    assert msg["To"] == "priya@example.com"
    assert msg["Subject"] == "Re: Offer letter - next steps"
    assert msg["In-Reply-To"] == "<abc@example.com>"
    assert msg["References"] == "<first@example.com> <abc@example.com>"
    assert msg.get_content().strip() == "Thanks, will do."
    again = rf.reply_message("me@gmail.com", dict(c, subject="RE: Offer"), "ok")
    assert again["Subject"] == "RE: Offer"
