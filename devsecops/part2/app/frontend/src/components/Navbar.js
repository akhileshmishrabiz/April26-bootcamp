import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { getPlayerName, setPlayerName, validatePlayerName } from '../utils/player';

function Navbar() {
  const [playerName, setPlayerNameState] = useState(getPlayerName());
  const [editing, setEditing] = useState(false);
  const [editValue, setEditValue] = useState(playerName);
  const [editError, setEditError] = useState(null);

  const savePlayerName = () => {
    const validationError = validatePlayerName(editValue);
    if (validationError) {
      setEditError(validationError);
      return;
    }
    const saved = setPlayerName(editValue);
    setPlayerNameState(saved);
    setEditing(false);
    setEditError(null);
  };

  return (
    <nav className="bg-gray-900 text-white">
      <div className="container mx-auto px-4 py-4">
        <div className="flex flex-wrap justify-between items-center gap-4">
          <Link to="/" className="text-xl font-bold hover:text-gray-300 transition-colors">
            DevOps Dojo
          </Link>

          <div className="flex flex-wrap items-center gap-4 md:gap-6">
            <Link to="/" className="hover:text-gray-300 transition-colors">
              Home
            </Link>
            <Link to="/leaderboard" className="hover:text-gray-300 transition-colors">
              Leaderboard
            </Link>
            <Link to="/wiki" className="hover:text-gray-300 transition-colors">
              Wiki
            </Link>
            <Link to="/manage-questions" className="hover:text-gray-300 text-sm">
              Manage
            </Link>

            {editing ? (
              <div className="flex items-center gap-2">
                <input
                  type="text"
                  value={editValue}
                  onChange={(e) => {
                    setEditValue(e.target.value);
                    setEditError(null);
                  }}
                  className="text-gray-900 px-2 py-1 rounded text-sm w-36"
                  placeholder="Your name"
                />
                <button
                  onClick={savePlayerName}
                  className="text-xs bg-blue-600 px-2 py-1 rounded hover:bg-blue-700"
                >
                  Save
                </button>
                <button
                  onClick={() => {
                    setEditing(false);
                    setEditError(null);
                  }}
                  className="text-xs text-gray-400 hover:text-white"
                >
                  Cancel
                </button>
                {editError && <span className="text-red-400 text-xs">{editError}</span>}
              </div>
            ) : (
              <button
                onClick={() => {
                  setEditValue(playerName);
                  setEditing(true);
                }}
                className="text-sm bg-gray-800 px-3 py-1 rounded-full hover:bg-gray-700 transition-colors"
                title="Click to change your leaderboard name"
              >
                {playerName || 'Set name'}
              </button>
            )}
          </div>
        </div>
      </div>
    </nav>
  );
}

export default Navbar;
