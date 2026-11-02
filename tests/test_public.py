"""Public discovery must never publish private ledger content or indexing flags."""
from html.parser import HTMLParser
import struct
from xml.etree import ElementTree

from test_ledger import add, client, login, workdir  # shared isolated backend fixtures


class Head(HTMLParser):
    def __init__(self):
        super().__init__()
        self.meta = {}
        self.canonical = None
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "meta":
            self.meta[attrs.get("name", attrs.get("property"))] = attrs.get("content")
        if tag == "link" and attrs.get("rel") == "canonical":
            self.canonical = attrs.get("href")


def test_public_metadata_and_canonical_are_independent_of_query_and_host(client):
    response = client.get("/about?utm_source=example", headers={"Host":"localhost"})
    assert response.status_code == 200
    assert response.headers["X-Robots-Tag"] == "index, follow"
    head = Head(); head.feed(response.get_data(as_text=True))
    assert head.canonical == "https://cobol.micutu.com/about"
    assert head.meta["og:url"] == head.canonical
    assert head.meta["og:image"].endswith("/static/public-card.png")
    assert head.meta["twitter:card"] == "summary_large_image"
    assert head.meta["description"] and "utm_source" not in head.canonical
    assert b'https://schema.org/SoftwareApplication' in response.data


def test_public_page_does_not_execute_the_private_backend(client, monkeypatch):
    import app
    def forbidden(*args, **kwargs):
        raise AssertionError("Public page invoked the financial backend")
    monkeypatch.setattr(app.subprocess, "Popen", forbidden)
    monkeypatch.delenv("LEDGER_PASS")
    assert client.get("/about").status_code == 200
    assert client.get("/sitemap.xml").status_code == 200


def test_private_data_and_indexing_stay_private(client):
    _, headers = login(client)
    secret = "PRIVATE-LEDGER-DO-NOT-EXPOSE"
    add(client, headers, "2026-11-01", "Hobby", secret, "-12.34")
    page = client.get("/about", headers=headers)
    assert secret.encode() not in page.data
    private = client.get("/", headers=headers)
    assert secret.encode() in private.data
    for path in ("/", "/?view=BUDGET", "/?view=RECURRING", "/health", "/missing"):
        assert "noindex" in client.get(path, headers=headers).headers["X-Robots-Tag"]


def test_sitemap_and_robots_only_describe_the_public_site(client):
    response = client.get("/sitemap.xml")
    assert response.mimetype == "application/xml"
    locations = [node.text for node in ElementTree.fromstring(response.data).iter()
                 if node.tag.endswith("}loc")]
    assert locations == ["https://cobol.micutu.com/about"]
    robots = client.get("/robots.txt").get_data(as_text=True)
    assert "Sitemap: https://cobol.micutu.com/sitemap.xml" in robots
    assert "Allow: /" in robots
    assert client.get("/about/").status_code == 308
    assert client.get("/about/").headers["Location"] == "/about"


def test_share_image_is_a_real_public_image(client):
    response = client.get("/static/public-card.png")
    assert response.status_code == 200 and response.mimetype == "image/png"
    assert response.data.startswith(b"\x89PNG\r\n\x1a\n")
    assert struct.unpack(">II", response.data[16:24]) == (1200, 630)
    assert response.headers["X-Robots-Tag"] == "index, follow"
