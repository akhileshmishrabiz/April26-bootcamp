import React, { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  fetchLeaderboard,
  fetchLeaderboardStats,
  fetchPlayerHistory,
  fetchTopics,
} from '../services/quizApi';
import { getPlayerName, validatePlayerName } from '../utils/player';

function formatTime(seconds) {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return mins > 0 ? `${mins}m ${secs}s` : `${secs}s`;
}

function formatDate(iso) {
  return new Date(iso).toLocaleString();
}

function RankBadge({ rank }) {
  if (rank === 1) return <span className="text-yellow-500 font-bold">🥇</span>;
  if (rank === 2) return <span className="text-gray-400 font-bold">🥈</span>;
  if (rank === 3) return <span className="text-amber-700 font-bold">🥉</span>;
  return <span className="text-gray-500 font-medium">#{rank}</span>;
}

function Leaderboard() {
  const [scope, setScope] = useState('global');
  const [selectedTopic, setSelectedTopic] = useState('');
  const [topics, setTopics] = useState([]);
  const [entries, setEntries] = useState([]);
  const [stats, setStats] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [playerLookup, setPlayerLookup] = useState(getPlayerName());
  const [playerHistory, setPlayerHistory] = useState(null);
  const [historyLoading, setHistoryLoading] = useState(false);

  useEffect(() => {
    fetchTopics()
      .then(setTopics)
      .catch(() => {});
    fetchLeaderboardStats()
      .then(setStats)
      .catch(() => {});
  }, []);

  const loadLeaderboard = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await fetchLeaderboard({
        scope,
        topic: scope === 'topic' ? selectedTopic : null,
      });
      setEntries(data.entries || []);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, [scope, selectedTopic]);

  useEffect(() => {
    if (scope === 'topic' && !selectedTopic && topics.length > 0) {
      setSelectedTopic(topics[0].id);
      return;
    }
    if (scope === 'global' || selectedTopic) {
      loadLeaderboard();
    }
  }, [scope, selectedTopic, topics, loadLeaderboard]);

  const handlePlayerLookup = async (event) => {
    event.preventDefault();
    const validationError = validatePlayerName(playerLookup);
    if (validationError) {
      setError(validationError);
      return;
    }
    try {
      setHistoryLoading(true);
      setError(null);
      const data = await fetchPlayerHistory(playerLookup);
      setPlayerHistory(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setHistoryLoading(false);
    }
  };

  const isGlobal = scope === 'global';

  return (
    <div className="container mx-auto px-4 py-8 max-w-5xl">
      <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4 mb-8">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">Leaderboard</h1>
          <p className="text-gray-600 mt-1">
            Compete with others — best score per topic counts toward your ranking.
          </p>
        </div>
        <Link
          to="/"
          className="inline-flex items-center justify-center bg-blue-600 text-white px-5 py-2 rounded-lg hover:bg-blue-700 transition-colors"
        >
          Take a Quiz
        </Link>
      </div>

      {stats && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
          {[
            { label: 'Total Attempts', value: stats.total_attempts },
            { label: 'Unique Players', value: stats.unique_players },
            { label: 'Quizzes Passed', value: stats.total_passed },
            { label: 'Active Topics', value: stats.topics?.length || 0 },
          ].map((item) => (
            <div key={item.label} className="bg-white rounded-lg shadow p-4 text-center">
              <p className="text-2xl font-bold text-blue-600">{item.value}</p>
              <p className="text-sm text-gray-500">{item.label}</p>
            </div>
          ))}
        </div>
      )}

      <div className="bg-white rounded-lg shadow-md p-4 mb-6">
        <div className="flex flex-wrap gap-2 mb-4">
          <button
            onClick={() => setScope('global')}
            className={`px-4 py-2 rounded-lg font-medium transition-colors ${
              isGlobal ? 'bg-blue-600 text-white' : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
            }`}
          >
            Global
          </button>
          <button
            onClick={() => setScope('topic')}
            className={`px-4 py-2 rounded-lg font-medium transition-colors ${
              !isGlobal ? 'bg-blue-600 text-white' : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
            }`}
          >
            By Topic
          </button>
        </div>

        {!isGlobal && (
          <select
            value={selectedTopic}
            onChange={(e) => setSelectedTopic(e.target.value)}
            className="w-full md:w-auto border border-gray-300 rounded-lg px-4 py-2 mb-4"
          >
            {topics.map((topic) => (
              <option key={topic.id} value={topic.id}>
                {topic.title}
              </option>
            ))}
          </select>
        )}

        {error && (
          <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-lg mb-4">
            {error}
          </div>
        )}

        {loading ? (
          <p className="text-center py-8 text-gray-500">Loading rankings...</p>
        ) : entries.length === 0 ? (
          <p className="text-center py-8 text-gray-500">
            No scores yet. Be the first to take a quiz!
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left">
              <thead>
                <tr className="border-b border-gray-200 text-sm text-gray-500 uppercase">
                  <th className="py-3 pr-4">Rank</th>
                  <th className="py-3 pr-4">Player</th>
                  {isGlobal ? (
                    <>
                      <th className="py-3 pr-4">Total Points</th>
                      <th className="py-3 pr-4">Avg Score</th>
                      <th className="py-3 pr-4">Passed</th>
                    </>
                  ) : (
                    <>
                      <th className="py-3 pr-4">Score</th>
                      <th className="py-3 pr-4">Correct</th>
                      <th className="py-3 pr-4">Time</th>
                      <th className="py-3 pr-4">Date</th>
                    </>
                  )}
                </tr>
              </thead>
              <tbody>
                {entries.map((entry) => (
                  <tr
                    key={`${entry.player_name}-${entry.rank}`}
                    className={`border-b border-gray-100 hover:bg-gray-50 ${
                      entry.player_name.toLowerCase() === getPlayerName().toLowerCase()
                        ? 'bg-blue-50'
                        : ''
                    }`}
                  >
                    <td className="py-3 pr-4">
                      <RankBadge rank={entry.rank} />
                    </td>
                    <td className="py-3 pr-4 font-medium text-gray-900">{entry.player_name}</td>
                    {isGlobal ? (
                      <>
                        <td className="py-3 pr-4">{entry.total_points}</td>
                        <td className="py-3 pr-4">{entry.average_score}%</td>
                        <td className="py-3 pr-4">
                          {entry.quizzes_passed}/{entry.quizzes_taken}
                        </td>
                      </>
                    ) : (
                      <>
                        <td className="py-3 pr-4">
                          <span
                            className={`font-semibold ${
                              entry.passed ? 'text-green-600' : 'text-orange-600'
                            }`}
                          >
                            {entry.score}%
                          </span>
                        </td>
                        <td className="py-3 pr-4">
                          {entry.correct_count}/{entry.total_questions}
                        </td>
                        <td className="py-3 pr-4">{formatTime(entry.time_taken_seconds)}</td>
                        <td className="py-3 pr-4 text-sm text-gray-500">
                          {formatDate(entry.completed_at)}
                        </td>
                      </>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="bg-white rounded-lg shadow-md p-6">
        <h2 className="text-xl font-bold mb-4">Your Quiz History</h2>
        <form onSubmit={handlePlayerLookup} className="flex flex-col sm:flex-row gap-3 mb-4">
          <input
            type="text"
            value={playerLookup}
            onChange={(e) => setPlayerLookup(e.target.value)}
            placeholder="Enter your player name"
            className="flex-1 border border-gray-300 rounded-lg px-4 py-2"
          />
          <button
            type="submit"
            disabled={historyLoading}
            className="bg-gray-800 text-white px-6 py-2 rounded-lg hover:bg-gray-900 disabled:opacity-50"
          >
            {historyLoading ? 'Loading...' : 'View History'}
          </button>
        </form>

        {playerHistory?.summary && (
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
            <div className="bg-gray-50 rounded-lg p-3 text-center">
              <p className="text-lg font-bold">{playerHistory.summary.attempts}</p>
              <p className="text-xs text-gray-500">Attempts</p>
            </div>
            <div className="bg-gray-50 rounded-lg p-3 text-center">
              <p className="text-lg font-bold">{playerHistory.summary.best_score}%</p>
              <p className="text-xs text-gray-500">Best Score</p>
            </div>
            <div className="bg-gray-50 rounded-lg p-3 text-center">
              <p className="text-lg font-bold">{playerHistory.summary.average_score}%</p>
              <p className="text-xs text-gray-500">Average</p>
            </div>
            <div className="bg-gray-50 rounded-lg p-3 text-center">
              <p className="text-lg font-bold">{playerHistory.summary.quizzes_passed}</p>
              <p className="text-xs text-gray-500">Passed</p>
            </div>
          </div>
        )}

        {playerHistory?.history?.length > 0 && (
          <div className="space-y-2">
            {playerHistory.history.map((attempt) => (
              <div
                key={attempt.id}
                className="flex flex-wrap items-center justify-between gap-2 border border-gray-100 rounded-lg px-4 py-3"
              >
                <div>
                  <p className="font-medium">{attempt.topic_name}</p>
                  <p className="text-sm text-gray-500">{formatDate(attempt.completed_at)}</p>
                </div>
                <div className="flex items-center gap-4">
                  <span
                    className={`font-bold ${
                      attempt.passed ? 'text-green-600' : 'text-orange-600'
                    }`}
                  >
                    {attempt.score}%
                  </span>
                  <span className="text-sm text-gray-500">
                    {attempt.correct_count}/{attempt.total_questions} ·{' '}
                    {formatTime(attempt.time_taken_seconds)}
                  </span>
                  <Link
                    to={`/quiz/${attempt.topic_slug}`}
                    className="text-sm text-blue-600 hover:underline"
                  >
                    Retry
                  </Link>
                </div>
              </div>
            ))}
          </div>
        )}

        {playerHistory && playerHistory.history?.length === 0 && (
          <p className="text-gray-500">No quiz attempts found for this player.</p>
        )}
      </div>
    </div>
  );
}

export default Leaderboard;
