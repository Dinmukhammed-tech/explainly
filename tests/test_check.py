"""The score is counted by Python, whatever the model says."""

from app import check

POINTS = [
    {"point": "A thread lives inside a process.", "label": "inside process", "slide": 11},
    {"point": "Threads share memory.", "label": "shared memory", "slide": 12},
    {"point": "Thread switch is faster.", "label": "context switch", "slide": 13},
]


def fake_model(results):
    return lambda *args: {"results": results}


def test_score_counts_only_covered_points(monkeypatch):
    monkeypatch.setattr(check.config, "llm_is_configured", lambda: True)
    monkeypatch.setattr(
        check,
        "_ask_model",
        fake_model([{"index": 1, "covered": True, "evidence": "inside"}, {"index": 2, "covered": False}]),
    )
    result = check.check_answer("q", POINTS, "a thread is inside a process")

    assert result["score"] == "1/3"
    assert result["mastery"] == 0.33
    assert [row["label"] for row in result["missed"]] == ["shared memory", "context switch"]
    assert result["missed"][0]["slide"] == 12


def test_point_the_model_forgot_is_missed(monkeypatch):
    monkeypatch.setattr(check.config, "llm_is_configured", lambda: True)
    monkeypatch.setattr(check, "_ask_model", fake_model([]))

    assert check.check_answer("q", POINTS, "anything")["score"] == "0/3"


def test_offline_check_rejects_an_answer_about_another_topic():
    result = check.check_answer("q", POINTS, "Round Robin gives every process a time slice.")

    assert result["score"] == "0/3"


def test_two_topics_with_one_title_become_one():
    from app import rubric

    raw = {"topics": [
        {"title": "Threads", "question": "What is a thread?", "key_points": [{"point": "Lives in a process.", "slide": 2}]},
        {"title": "threads", "question": "Why are they fast?", "key_points": [{"point": "Switching is cheap.", "slide": 99}]},
    ]}
    topics = rubric.normalize(raw)["topics"]

    assert len(topics) == 1
    assert [k["point"] for k in topics[0]["key_points"]] == ["Lives in a process.", "Switching is cheap."]


def test_no_quote_from_the_student_means_no_credit(monkeypatch):
    monkeypatch.setattr(check.config, "llm_is_configured", lambda: True)
    monkeypatch.setattr(check, "_ask_model", fake_model([{"index": 1, "covered": True, "evidence": ""}]))

    assert check.check_answer("q", POINTS, "anything")["score"] == "0/3"


def test_an_invented_quote_is_not_a_quote():
    answer = "Um, threads of the same process use the same memory, and a thread switch is quicker."

    assert check.is_quote("threads of the same process use the same memory", answer)
    assert check.is_quote("Threads of the same process use the same memory.", answer)
    assert not check.is_quote("a thread is a unit of execution that lives inside a process", answer)
    assert not check.is_quote("", answer)


def test_only_a_clear_said_with_a_real_quote_counts(monkeypatch):
    replies = iter([
        {"evidence": "a thread is inside a process", "verdict": "said"},
        {"evidence": "a thread is inside a process", "verdict": "hinted"},
        {"evidence": "switching threads is very fast", "verdict": "said"},  # invented
    ])
    monkeypatch.setattr(check.config, "llm_is_configured", lambda: True)
    monkeypatch.setattr(check, "ask_json", lambda *args: next(replies))

    result = check.check_answer("q", POINTS, "I think a thread is inside a process.")

    assert result["score"] == "1/3"
    assert [row["label"] for row in result["named"]] == ["inside process"]


LIST_SLIDE = """・Parsing in a compiler.
・Java virtual machine.
・Undo in a word processor.
・Back button in a Web browser.
・...
53
Stack applications"""


def test_a_list_slide_gives_one_key_point_for_every_item():
    from app import rubric

    slides = [
        {"slide": 53, "text": LIST_SLIDE},
        {"slide": 55, "text": "Goal. Evaluate infix expressions.\nTwo-stack algorithm."},
    ]
    found = {"topics": [{"title": "Stack applications", "question": "Name them.", "key_points": [
        {"point": "Stacks are used in parsing compilers.", "label": "parsing", "slide": 53},
        {"point": "Stacks are used in the JVM.", "label": "JVM", "slide": 53},
        {"point": "Stacks evaluate arithmetic expressions.", "label": "expressions", "slide": 55},
        {"point": "Stacks are used for undo in word processors.", "label": "undo", "slide": 54},
    ]}]}

    points = rubric.expand_lists(found, slides)["topics"][0]["key_points"]

    assert [p["point"] for p in points] == [
        "Parsing in a compiler.",
        "Java virtual machine.",
        "Undo in a word processor.",
        "Back button in a Web browser.",
        "Stacks evaluate arithmetic expressions.",
    ]


def test_sentences_and_code_are_not_a_list():
    from app import rubric

    sentences = "Deadlocks\nA deadlock is when processes wait for each other forever.\n" * 4
    code = "Stack code\npublic boolean isEmpty()\n{ return N == 0; }\nprivate int N = 0;\nreturn s[--N];"

    assert rubric.list_items(sentences) == []
    assert rubric.list_items(code) == []


def test_the_outline_repeated_on_several_slides_is_not_a_list():
    from app import rubric

    outline = "・stacks\n・resizing arrays\n・queues\n・generics"
    slides = [{"slide": 1, "text": outline}, {"slide": 4, "text": outline}]
    found = {"topics": [{"title": "T", "question": "Q", "key_points": [
        {"point": "A stack is last in, first out.", "label": "LIFO", "slide": 4},
    ]}]}

    points = rubric.expand_lists(found, slides)["topics"][0]["key_points"]

    assert [p["point"] for p in points] == ["A stack is last in, first out."]
