import React from 'react';
import { Link } from 'react-router-dom';

function Navbar() {
  return (
    <nav className="bg-gradient-to-r from-pink-600 via-fuchsia-600 to-rose-500 p-4 shadow-lg">
      <div className="container mx-auto">
        <div className="flex justify-between items-center">
          <Link to="/" className="text-white text-xl font-extrabold tracking-tight">
            devopsdejo-frombootcamp
          </Link>
          <div className="space-x-6">
            <Link to="/" className="text-white hover:text-pink-100">
              Home
            </Link>
            <Link to="/wiki" className="text-white hover:text-pink-100">
              Wiki
            </Link>
            <Link to="/manage-questions" className="text-white hover:text-pink-100">
              Manage Questions
            </Link>
          </div>
        </div>
      </div>
    </nav>
  );
}

export default Navbar;
