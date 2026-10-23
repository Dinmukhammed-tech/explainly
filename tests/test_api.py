"""The whole path through the server: subject -> upload -> answer -> topic map."""

from pathlib import Path

LECTURE = Path(__file__).parent.parent / "samples" / "os_lecture.pptx"


def upload(client) -> dict:
    subject = client.post("/subjects", json={"name": "Operating Systems"}).json()
    with LECTURE.open("rb") as file:
        response = client.post(f"/subjects/{subject['id']}/materials", files={"file": (LECTURE.name, file)})
    assert response.status_code == 201, response.text
    return response.json()["subject"]


def test_upload_makes_topics(client):
    subject = upload(client)

    assert subject["topics"] == 4
    assert subject["new"] == 4
    assert subject["topic_list"][0]["title"] == "Processes and threads"
    assert subject["topic_list"][0]["status"] == "new"


def test_answer_is_scored_and_missed_points_link_to_a_slide(client):
    topic = upload(client)["topic_list"][0]

    result = client.post(
        f"/topics/{topic['id']}/answer",
        data={"text": "Round Robin gives every process a fixed time slice."},
    ).json()

    assert result["score"] == "0/4"
    assert all(row["slide"] == 2 and row["snippet"] for row in result["missed"])
    assert result["topic"]["percent"] == 0
    assert result["topic"]["status"] == "weak"
    assert result["topic"]["last_missed"]


def test_topic_map_uses_the_average_of_the_last_attempts(client):
    topic = upload(client)["topic_list"][0]
    full = (
        "A process is a running program with its own address space. "
        "A thread is a unit of execution that lives inside a process. "
        "Threads of one process share the same memory, processes do not. "
        "Switching between threads is faster than switching between processes."
    )
    client.post(f"/topics/{topic['id']}/answer", data={"text": "Round Robin gives a time slice."})
    after = client.post(f"/topics/{topic['id']}/answer", data={"text": full}).json()

    assert after["score"] == "4/4"
    assert after["topic"]["percent"] == 50  # (0 + 100) / 2, one good answer is not "green" yet
    assert after["topic"]["recent_scores"] == ["0/4", "4/4"]


def test_next_topic_is_the_weakest_one(client):
    subject = upload(client)
    weak = subject["topic_list"][2]
    client.post(f"/topics/{weak['id']}/answer", data={"text": "I do not know."})

    assert client.get(f"/subjects/{subject['id']}/next").json()["id"] == weak["id"]


def test_wrong_file_type_and_empty_answer_are_refused(client):
    subject = client.post("/subjects", json={"name": "X"}).json()
    bad = client.post(f"/subjects/{subject['id']}/materials", files={"file": ("notes.txt", b"hello")})
    assert bad.status_code == 415

    topic = upload(client)["topic_list"][0]
    assert client.post(f"/topics/{topic['id']}/answer", data={"text": "  "}).status_code == 422
