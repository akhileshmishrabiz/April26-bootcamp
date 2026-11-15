import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { startQuiz, submitQuiz } from '../services/quizApi';
import {
  getPlayerName,
  setPlayerName,
  validatePlayerName,
} from '../utils/player';

function formatTime(seconds) {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
}

function PlayerNameModal({ onConfirm }) {
  const [name, setName] = useState(getPlayerName());
  const [error, setError] = useState(null);

  const handleSubmit = (event) => {
    event.preventDefault();
    const validationError = validatePlayerName(name);
    if (validationError) {
      setError(validationError);
      return;
    }
    const saved = setPlayerName(name);
    onConfirm(saved);
  };

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-xl shadow-xl max-w-md w-full p-6">
        <h2 className="text-2xl font-bold mb-2">Enter Your Name</h2>
        <p className="text-gray-600 mb-6">
          Your name appears on the leaderboard. Pick something you&apos;ll recognize.
        </p>
        <form onSubmit={handleSubmit}>
          <input
            type="text"
            value={name}
            onChange={(e) => {
              setName(e.target.value);
              setError(null);
            }}
            placeholder="e.g. DevOps Ninja"
            className="w-full border border-gray-300 rounded-lg px-4 py-3 mb-2 focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            autoFocus
          />
          {error && <p className="text-red-600 text-sm mb-3">{error}</p>}
          <button
            type="submit"
            className="w-full bg-blue-600 text-white py-3 rounded-lg font-medium hover:bg-blue-700 transition-colors"
          >
            Start Quiz
          </button>
        </form>
      </div>
    </div>
  );
}

function Quiz() {
  const { topic } = useParams();
  const navigate = useNavigate();
  const [quiz, setQuiz] = useState(null);
  const [answers, setAnswers] = useState({});
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(true);
  const [showNameModal, setShowNameModal] = useState(!getPlayerName());
  const [playerName, setPlayerNameState] = useState(getPlayerName());
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const [showReview, setShowReview] = useState(false);
  const timerRef = useRef(null);
  const startTimeRef = useRef(null);

  const stopTimer = useCallback(() => {
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  const startTimer = useCallback(() => {
    stopTimer();
    startTimeRef.current = Date.now();
    setElapsedSeconds(0);
    timerRef.current = setInterval(() => {
      setElapsedSeconds(Math.floor((Date.now() - startTimeRef.current) / 1000));
    }, 1000);
  }, [stopTimer]);

  const loadQuiz = useCallback(
    async (name) => {
      try {
        setLoading(true);
        setError(null);
        setResult(null);
        setAnswers({});
        setShowReview(false);
        const data = await startQuiz(topic, name);
        setQuiz(data);
        startTimer();
      } catch (err) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    },
    [topic, startTimer]
  );

  useEffect(() => {
    if (playerName && !showNameModal) {
      loadQuiz(playerName);
    }
    return () => stopTimer();
  }, [playerName, showNameModal, loadQuiz, stopTimer]);

  const handleNameConfirm = (name) => {
    setPlayerNameState(name);
    setShowNameModal(false);
  };

  const handleAnswerSelect = (questionId, answerIndex) => {
    setAnswers((prev) => ({ ...prev, [questionId]: answerIndex }));
  };

  const answeredCount = Object.keys(answers).length;
  const totalQuestions = quiz?.questions?.length || 0;
  const progress = totalQuestions ? Math.round((answeredCount / totalQuestions) * 100) : 0;

  const handleSubmit = async () => {
    if (answeredCount < totalQuestions) {
      setError(`Please answer all questions (${answeredCount}/${totalQuestions} answered)`);
      return;
    }

    try {
      setError(null);
      stopTimer();
      const data = await submitQuiz(quiz.session_id, answers, elapsedSeconds);
      setResult(data);
    } catch (err) {
      setError(err.message);
      startTimer();
    }
  };

  const handleTryAgain = () => {
    loadQuiz(playerName);
  };

  if (showNameModal) {
    return <PlayerNameModal onConfirm={handleNameConfirm} />;
  }

  if (loading) {
    return (
      <div className="container mx-auto px-4 py-16 text-center">
        <div className="inline-block animate-pulse text-gray-500">Loading quiz...</div>
      </div>
    );
  }

  if (error && !quiz) {
    return (
      <div className="container mx-auto px-4 py-8 max-w-3xl">
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-lg">
          <p>{error}</p>
          <button
            onClick={() => navigate('/')}
            className="mt-4 bg-red-600 text-white px-4 py-2 rounded-lg hover:bg-red-700"
          >
            Return to Home
          </button>
        </div>
      </div>
    );
  }

  if (!quiz) {
    return (
      <div className="container mx-auto px-4 py-8 text-center text-gray-500">
        No quiz found.
      </div>
    );
  }

  return (
    <div className="container mx-auto px-4 py-8 max-w-3xl">
      {!result ? (
        <>
          <div className="flex flex-wrap items-center justify-between gap-4 mb-6">
            <div>
              <h1 className="text-3xl font-bold text-gray-900">{quiz.title}</h1>
              <p className="text-gray-600 mt-1">
                Playing as <span className="font-medium text-gray-800">{playerName}</span>
              </p>
            </div>
            <div className="bg-gray-900 text-white px-4 py-2 rounded-lg font-mono text-lg">
              {formatTime(elapsedSeconds)}
            </div>
          </div>

          {quiz.total_questions > quiz.selected_questions && (
            <p className="mb-4 text-gray-600 text-sm">
              {quiz.selected_questions} random questions from a pool of {quiz.total_questions}.
            </p>
          )}

          <div className="mb-6">
            <div className="flex justify-between text-sm text-gray-600 mb-1">
              <span>
                Progress: {answeredCount}/{totalQuestions}
              </span>
              <span>{progress}%</span>
            </div>
            <div className="w-full bg-gray-200 rounded-full h-2">
              <div
                className="bg-blue-600 h-2 rounded-full transition-all duration-300"
                style={{ width: `${progress}%` }}
              />
            </div>
          </div>

          {error && (
            <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-lg mb-4">
              {error}
            </div>
          )}

          <div className="space-y-6">
            {quiz.questions.map((question, index) => (
              <div key={question.id} className="bg-white rounded-xl shadow-md p-6">
                <p className="text-lg font-medium mb-4 text-gray-900">
                  <span className="text-blue-600 mr-2">{index + 1}.</span>
                  {question.question}
                </p>
                <div className="space-y-2">
                  {question.options.map((option, optionIndex) => (
                    <label
                      key={optionIndex}
                      className={`flex items-center p-3 rounded-lg cursor-pointer border transition-colors ${
                        answers[question.id] === optionIndex
                          ? 'bg-blue-50 border-blue-300'
                          : 'border-gray-200 hover:bg-gray-50'
                      }`}
                    >
                      <input
                        type="radio"
                        name={`question-${question.id}`}
                        className="mr-3 accent-blue-600"
                        checked={answers[question.id] === optionIndex}
                        onChange={() => handleAnswerSelect(question.id, optionIndex)}
                      />
                      <span>{option}</span>
                    </label>
                  ))}
                </div>
              </div>
            ))}
          </div>

          <button
            onClick={handleSubmit}
            disabled={answeredCount < totalQuestions}
            className="w-full mt-8 bg-blue-600 text-white px-6 py-4 rounded-xl hover:bg-blue-700 font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Submit Quiz
          </button>
        </>
      ) : (
        <div className="space-y-6">
          <div className="bg-white rounded-xl shadow-md p-8 text-center">
            <h2 className="text-2xl font-bold mb-2">Quiz Complete!</h2>
            <p className="text-gray-600 mb-6">{result.topic_name}</p>

            <div
              className={`inline-block rounded-2xl px-8 py-6 mb-4 ${
                result.passed ? 'bg-green-50' : 'bg-orange-50'
              }`}
            >
              <p
                className={`text-5xl font-bold mb-1 ${
                  result.passed ? 'text-green-600' : 'text-orange-600'
                }`}
              >
                {Math.round(result.score)}%
              </p>
              <p className="text-gray-700">
                {result.correct} of {result.total} correct
              </p>
              <p className="text-sm text-gray-500 mt-2">
                Time: {formatTime(result.time_taken_seconds)} · Rank #{result.rank} on this topic
              </p>
            </div>

            <p
              className={`text-lg font-medium mb-6 ${
                result.passed ? 'text-green-700' : 'text-orange-700'
              }`}
            >
              {result.passed
                ? `Passed! (≥ ${result.pass_threshold}%)`
                : `Keep practicing — pass mark is ${result.pass_threshold}%`}
            </p>

            <div className="flex flex-wrap justify-center gap-3">
              <button
                onClick={handleTryAgain}
                className="bg-blue-600 text-white px-6 py-2 rounded-lg hover:bg-blue-700"
              >
                Try Again
              </button>
              <Link
                to="/leaderboard"
                className="bg-gray-800 text-white px-6 py-2 rounded-lg hover:bg-gray-900 inline-block"
              >
                View Leaderboard
              </Link>
              <button
                onClick={() => navigate('/')}
                className="bg-gray-200 text-gray-800 px-6 py-2 rounded-lg hover:bg-gray-300"
              >
                Home
              </button>
            </div>
          </div>

          <div className="bg-white rounded-xl shadow-md p-6">
            <button
              onClick={() => setShowReview(!showReview)}
              className="w-full flex items-center justify-between text-left font-medium text-gray-900"
            >
              <span>Question Review ({result.review?.length || 0})</span>
              <span>{showReview ? '▲' : '▼'}</span>
            </button>

            {showReview && result.review && (
              <div className="mt-4 space-y-4">
                {result.review.map((item, index) => (
                  <div
                    key={item.question_id}
                    className={`border rounded-lg p-4 ${
                      item.is_correct
                        ? 'border-green-200 bg-green-50'
                        : 'border-red-200 bg-red-50'
                    }`}
                  >
                    <p className="font-medium mb-2">
                      {index + 1}. {item.question}
                    </p>
                    <div className="space-y-1 text-sm">
                      {item.options.map((option, optIdx) => (
                        <p
                          key={optIdx}
                          className={`px-2 py-1 rounded ${
                            optIdx === item.correct_answer
                              ? 'bg-green-200 font-medium'
                              : optIdx === item.your_answer && !item.is_correct
                                ? 'bg-red-200 line-through'
                                : ''
                          }`}
                        >
                          {option}
                          {optIdx === item.correct_answer && ' ✓'}
                          {optIdx === item.your_answer && !item.is_correct && ' (your answer)'}
                        </p>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

export default Quiz;
