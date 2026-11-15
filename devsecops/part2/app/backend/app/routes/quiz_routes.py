from flask import current_app, jsonify, request

from app.cloudwatch_metrics import emit_quiz_submission
from app.models import db
from app.models.models import Question, QuizAttempt, QuizSession, Topic
from app.quiz_logic import create_quiz_session, get_player_rank
from app.validators import validate_player_name

from . import quiz_bp


@quiz_bp.route("/<topic_slug>/start", methods=["POST"])
def start_quiz(topic_slug):
    data = request.get_json(silent=True) or {}
    player_name, error = validate_player_name(data.get("player_name"))
    if error:
        return jsonify({"error": error}), 400

    topic = Topic.query.filter_by(slug=topic_slug).first_or_404()
    all_questions = Question.query.filter_by(topic_id=topic.id).all()

    if not all_questions:
        return jsonify(
            {
                "error": "No questions available for this topic yet",
                "title": topic.name,
                "questions": [],
                "total_questions": 0,
            }
        ), 404

    session, public_questions = create_quiz_session(topic, player_name)
    db.session.add(session)
    db.session.commit()

    return jsonify(
        {
            "session_id": session.id,
            "title": topic.name,
            "topic_slug": topic.slug,
            "player_name": player_name,
            "questions": public_questions,
            "total_questions": len(all_questions),
            "selected_questions": len(public_questions),
            "pass_threshold": current_app.config.get("PASS_THRESHOLD", 70),
            "expires_at": session.expires_at.isoformat(),
        }
    )


@quiz_bp.route("/submit", methods=["POST"])
def submit_quiz():
    data = request.get_json(silent=True) or {}
    session_id = data.get("session_id")
    answers = data.get("answers")
    time_taken_seconds = data.get("time_taken_seconds", 0)

    if not session_id or not answers:
        return jsonify({"error": "session_id and answers are required"}), 400

    try:
        time_taken_seconds = max(0, int(time_taken_seconds))
    except (TypeError, ValueError):
        return jsonify({"error": "time_taken_seconds must be a number"}), 400

    session = QuizSession.query.get(session_id)
    if not session:
        return jsonify({"error": "Quiz session not found"}), 404
    if session.submitted:
        return jsonify({"error": "This quiz session was already submitted"}), 409
    if session.is_expired():
        return jsonify({"error": "Quiz session expired. Please start a new quiz."}), 410

    expected_ids = {str(item["id"]) for item in session.question_data}
    if set(answers.keys()) != expected_ids:
        return jsonify({"error": "Please answer all questions before submitting"}), 400

    correct_count, total_questions, score, review = session.grade(answers)
    pass_threshold = current_app.config.get("PASS_THRESHOLD", 70)
    passed = score >= pass_threshold

    attempt = QuizAttempt(
        player_name=session.player_name,
        topic_id=session.topic_id,
        score=score,
        correct_count=correct_count,
        total_questions=total_questions,
        time_taken_seconds=time_taken_seconds,
        passed=passed,
    )
    session.submitted = True
    db.session.add(attempt)
    db.session.commit()

    emit_quiz_submission(session.topic.slug, passed=passed)
    rank = get_player_rank(session.topic_id, session.player_name)

    return jsonify(
        {
            "score": score,
            "correct": correct_count,
            "total": total_questions,
            "passed": passed,
            "pass_threshold": pass_threshold,
            "time_taken_seconds": time_taken_seconds,
            "rank": rank,
            "player_name": session.player_name,
            "topic_slug": session.topic.slug,
            "topic_name": session.topic.name,
            "review": review,
        }
    )


@quiz_bp.route("/questions", methods=["GET", "POST"])
def manage_questions():
    if request.method == "POST":
        data = request.get_json()
        if not all(
            k in data for k in ("topic_slug", "question_text", "options", "correct_answer")
        ):
            return jsonify({"error": "Missing required fields"}), 400

        topic = Topic.query.filter_by(slug=data["topic_slug"]).first()
        if not topic:
            topic_name = data["topic_slug"].replace("-", " ").title()
            topic = Topic(
                name=topic_name,
                description=f"Questions about {topic_name}",
                slug=data["topic_slug"],
            )
            db.session.add(topic)
            db.session.commit()

        try:
            question = Question(
                topic_id=topic.id,
                question_text=data["question_text"],
                options=data["options"],
                correct_answer=data["correct_answer"],
            )
            db.session.add(question)
            db.session.commit()
            return jsonify(question.to_admin_dict()), 201
        except Exception as exc:
            db.session.rollback()
            return jsonify({"error": str(exc)}), 400

    questions = Question.query.all()
    return jsonify([q.to_admin_dict() for q in questions])


@quiz_bp.route("/questions/bulk", methods=["POST"])
def bulk_upload_questions():
    if not request.is_json:
        return jsonify({"error": "Content-Type must be application/json"}), 400

    questions_data = request.get_json()
    if not isinstance(questions_data, list):
        return jsonify({"error": "Expected a list of questions"}), 400

    success_count = 0
    failed_count = 0
    errors = []
    valid_questions = []
    created_topics = []

    for index, question_data in enumerate(questions_data):
        try:
            if not question_data or not any(question_data.values()):
                continue

            if not all(
                k in question_data
                for k in ("topic_slug", "question_text", "options", "correct_answer")
            ):
                failed_count += 1
                errors.append(f"Row {index + 1}: Missing required fields")
                continue

            if not question_data["question_text"] or not question_data["question_text"].strip():
                failed_count += 1
                errors.append(f"Row {index + 1}: Empty question text")
                continue

            if not isinstance(question_data["options"], list) or len(question_data["options"]) != 4:
                failed_count += 1
                errors.append(f"Row {index + 1}: Invalid options format")
                continue

            if any(opt is None or str(opt).strip() == "" for opt in question_data["options"]):
                failed_count += 1
                errors.append(f"Row {index + 1}: Empty options not allowed")
                continue

            try:
                correct_answer = int(question_data["correct_answer"])
                if not 0 <= correct_answer <= 3:
                    raise ValueError("Correct answer must be between 0 and 3")
            except (ValueError, TypeError):
                failed_count += 1
                errors.append(f"Row {index + 1}: Invalid correct_answer value")
                continue

            topic_slug = question_data["topic_slug"].strip()
            topic = Topic.query.filter_by(slug=topic_slug).first()

            if not topic:
                if topic_slug not in created_topics:
                    topic_name = topic_slug.replace("-", " ").title()
                    topic = Topic(
                        name=topic_name,
                        description=f"Questions about {topic_name}",
                        slug=topic_slug,
                    )
                    db.session.add(topic)
                    created_topics.append(topic_slug)
                else:
                    topic = Topic.query.filter_by(slug=topic_slug).first()

            valid_questions.append(
                {
                    "topic_id": topic.id if topic.id else None,
                    "topic_slug": topic_slug,
                    "question_text": question_data["question_text"].strip(),
                    "options": [str(opt).strip() for opt in question_data["options"]],
                    "correct_answer": correct_answer,
                }
            )
        except Exception as exc:
            failed_count += 1
            errors.append(f"Row {index + 1}: {str(exc)}")

    if created_topics:
        try:
            db.session.commit()
        except Exception as exc:
            db.session.rollback()
            return jsonify(
                {"error": "Failed to create new topics", "detail": str(exc), "errors": errors}
            ), 400

    if valid_questions:
        try:
            for question_data in valid_questions:
                if question_data["topic_id"] is None:
                    topic = Topic.query.filter_by(slug=question_data["topic_slug"]).first()
                    question_data["topic_id"] = topic.id
                question_data.pop("topic_slug")
                db.session.add(Question(**question_data))
                success_count += 1
            db.session.commit()
        except Exception as exc:
            db.session.rollback()
            return jsonify(
                {
                    "error": "Failed to commit questions to database",
                    "detail": str(exc),
                    "errors": errors,
                }
            ), 400

    return jsonify(
        {
            "success": success_count,
            "failed": failed_count,
            "topics_created": len(created_topics),
            "errors": errors if errors else None,
        }
    )
