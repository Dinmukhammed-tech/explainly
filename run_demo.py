#!/usr/bin/env python3
"""Explainly, milestone 1: the whole idea in the terminal.

    python run_demo.py lecture.pdf          # build the rubric, then ask you
    python run_demo.py lecture.pdf --topic 2
    python run_demo.py --rubric my.json     # reuse a saved rubric, no API cost
    python run_demo.py --fake               # try the loop with no API key

You type the answer here. Voice comes in milestone 2.
"""

import argparse

from app import extract, rubric as rubric_mod
from app.check import check_answer

FAKE_RUBRIC = {
    "topics": [
        {
            "title": "Processes and threads",
            "question": "Explain the difference between a process and a thread.",
            "key_points": [
                {"point": "A thread lives inside a process.", "slide": 11},
                {"point": "Threads of one process share the same memory; processes do not.", "slide": 12},
                {"point": "Switching between threads is faster than between processes.", "slide": 13},
            ],
        }
    ]
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("lecture", nargs="?", help="a .pdf or .pptx lecture")
    parser.add_argument("--rubric", help="reuse a rubric JSON file")
    parser.add_argument("--save", default="rubric.json", help="where to save the rubric")
    parser.add_argument("--topic", type=int, default=1, help="which topic to ask (1 = first)")
    parser.add_argument("--fake", action="store_true", help="use a built-in example, no API")
    args = parser.parse_args()

    if args.fake:
        data = FAKE_RUBRIC
    elif args.rubric:
        data = rubric_mod.load(args.rubric)
    elif args.lecture:
        slides = extract.read_lecture(args.lecture)
        print(f"Read {len(slides)} slides with text.")
        print("Finding topics and key points...")
        data = rubric_mod.build_rubric(extract.as_prompt_text(slides))
        rubric_mod.save(data, args.save)
        print(f"Rubric saved to {args.save}\n")
    else:
        parser.error("give a lecture file, or --rubric FILE, or --fake")

    topics = data["topics"]
    if not 1 <= args.topic <= len(topics):
        parser.error(f"--topic must be between 1 and {len(topics)}")
    topic = topics[args.topic - 1]

    print("=" * 64)
    print(f"Topic: {topic['title']}")
    print(f"\nQUESTION: {topic['question']}")
    print("=" * 64)
    answer = input("\nYour answer (type it, in English):\n> ").strip()
    if not answer:
        print("No answer, nothing to check.")
        return

    if args.fake:
        print("\n--fake only shows the question. Add an API key to see the check.")
        return

    print("\nChecking against the lecture...\n")
    result = check_answer(topic["question"], topic["key_points"], answer)

    print(f"SCORE: {result['score']} key points\n")
    for row in result["named"]:
        print(f"  [ok]     {row['point']}")
        if row["evidence"]:
            print(f"           you said: \"{row['evidence']}\"")
    for row in result["missed"]:
        print(f"  [missed] {row['point']}")
        if row["slide"]:
            print(f"           read again: slide {row['slide']}")


if __name__ == "__main__":
    main()
