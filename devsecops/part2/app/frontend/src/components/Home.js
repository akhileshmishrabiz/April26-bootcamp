import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { fetchLeaderboardStats, fetchTopics } from '../services/quizApi';

function Home() {
  const [topics, setTopics] = useState([]);
  const [stats, setStats] = useState(null);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchTopics()
      .then((topicsData) => {
        setTopics(topicsData);
        return fetchLeaderboardStats()
          .then(setStats)
          .catch(() => null);
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, []);

  if (loading) {
    return (
      <div className="container mx-auto px-4 py-16 text-center text-gray-500">
        Loading...
      </div>
    );
  }

  if (error) {
    return (
      <div className="container mx-auto px-4 py-8">
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-lg">
          <p>Error loading platform: {error}</p>
          <p className="text-sm mt-1">Make sure the backend server is running.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-4 py-8">
      <div className="text-center mb-10">
        <h1 className="text-4xl font-bold text-gray-900 mb-3">DevOps Dojo</h1>
        <p className="text-lg text-gray-600 max-w-2xl mx-auto">
          Master DevOps concepts through interactive quizzes. Compete on the leaderboard
          and track your progress across topics.
        </p>
        <Link
          to="/leaderboard"
          className="inline-block mt-6 bg-gray-900 text-white px-6 py-3 rounded-lg hover:bg-gray-800 transition-colors"
        >
          View Leaderboard →
        </Link>
      </div>

      {stats && stats.total_attempts > 0 && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-10 max-w-3xl mx-auto">
          {[
            { label: 'Quizzes Taken', value: stats.total_attempts },
            { label: 'Players', value: stats.unique_players },
            { label: 'Passed', value: stats.total_passed },
            { label: 'Topics', value: topics.length },
          ].map((item) => (
            <div key={item.label} className="bg-white rounded-lg shadow text-center p-4">
              <p className="text-2xl font-bold text-blue-600">{item.value}</p>
              <p className="text-sm text-gray-500">{item.label}</p>
            </div>
          ))}
        </div>
      )}

      <h2 className="text-2xl font-bold mb-6 text-gray-900">Choose a Topic</h2>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {topics.map((topic) => (
          <div
            key={topic.id}
            className="bg-white rounded-xl shadow-md p-6 hover:shadow-lg transition-shadow flex flex-col"
          >
            <h3 className="text-xl font-bold mb-2 text-gray-900">{topic.title}</h3>
            <p className="text-gray-600 mb-4 flex-grow">{topic.description}</p>
            {topic.question_count != null && (
              <p className="text-sm text-gray-400 mb-4">
                {topic.question_count} questions available
              </p>
            )}
            <Link
              to={`/quiz/${topic.id}`}
              className="inline-block text-center bg-blue-600 text-white px-6 py-2 rounded-lg hover:bg-blue-700 transition-colors"
            >
              Take Quiz
            </Link>
          </div>
        ))}
      </div>
    </div>
  );
}

export default Home;
