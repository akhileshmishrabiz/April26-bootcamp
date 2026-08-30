import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import API_URL from '../config/api';

const cardAccents = [
  { bar: 'from-pink-500 to-rose-400', btn: 'bg-pink-500 hover:bg-pink-600', chip: 'bg-pink-100 text-pink-700' },
  { bar: 'from-fuchsia-500 to-purple-400', btn: 'bg-fuchsia-500 hover:bg-fuchsia-600', chip: 'bg-fuchsia-100 text-fuchsia-700' },
  { bar: 'from-orange-400 to-pink-500', btn: 'bg-orange-500 hover:bg-orange-600', chip: 'bg-orange-100 text-orange-700' },
  { bar: 'from-rose-500 to-pink-400', btn: 'bg-rose-500 hover:bg-rose-600', chip: 'bg-rose-100 text-rose-700' },
  { bar: 'from-violet-500 to-fuchsia-400', btn: 'bg-violet-500 hover:bg-violet-600', chip: 'bg-violet-100 text-violet-700' },
  { bar: 'from-amber-400 to-rose-400', btn: 'bg-amber-500 hover:bg-amber-600', chip: 'bg-amber-100 text-amber-700' },
];

function Home() {
  const [topics, setTopics] = useState([]);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchTopics = async () => {
      try {
        setLoading(true);
        const response = await fetch(`${API_URL}/api/topics`, {
          method: 'GET',
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json'
          }
        });

        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();
        console.log('Fetched topics:', data);
        setTopics(data);
      } catch (err) {
        console.error('Error fetching topics:', err);
        setError(err.message);
      } finally {
        setLoading(false);
      }
    };

    fetchTopics();
  }, []);

  if (loading) {
    return (
      <div className="container mx-auto px-4 py-8">
        <p className="text-center text-pink-600 font-medium">Loading...</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="container mx-auto px-4 py-8">
        <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">
          <p>Error loading topics: {error}</p>
          <p>Please make sure the backend server is running and accessible</p>
        </div>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-4 py-10">
      <div className="relative overflow-hidden rounded-3xl mb-12 px-6 py-14 text-center text-white shadow-xl bg-gradient-to-r from-pink-500 via-fuchsia-500 to-orange-400">
        <div className="absolute -top-10 -left-10 h-32 w-32 rounded-full bg-yellow-300/40 blur-2xl" />
        <div className="absolute -bottom-12 -right-8 h-40 w-40 rounded-full bg-violet-400/40 blur-2xl" />
        <p className="relative uppercase tracking-[0.25em] text-sm font-semibold text-pink-100 mb-3">
          from bootcamp
        </p>
        <h1 className="relative text-4xl md:text-5xl font-extrabold mb-4 drop-shadow-sm">
          devopsdejo-frombootcamp
        </h1>
        <p className="relative text-lg text-pink-50 max-w-2xl mx-auto">
          Master DevOps concepts through interactive learning and quizzes.
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {topics.map((topic, index) => {
          const accent = cardAccents[index % cardAccents.length];
          return (
            <div
              key={topic.id}
              className="bg-white rounded-2xl shadow-lg overflow-hidden hover:shadow-2xl hover:-translate-y-1 transition-all"
            >
              <div className={`h-2 bg-gradient-to-r ${accent.bar}`} />
              <div className="p-6">
                <span className={`inline-block text-xs font-semibold px-2 py-1 rounded-full mb-3 ${accent.chip}`}>
                  Topic
                </span>
                <h2 className="text-2xl font-bold mb-2 text-gray-800">{topic.title}</h2>
                <p className="text-gray-600 mb-4">{topic.description}</p>
                <Link
                  to={`/quiz/${topic.id}`}
                  className={`inline-block text-white px-6 py-2 rounded-lg transition-colors ${accent.btn}`}
                >
                  Take Quiz
                </Link>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

export default Home;
