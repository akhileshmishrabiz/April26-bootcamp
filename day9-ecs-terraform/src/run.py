from app import create_app

# gunicorn run:app imports this module and uses `app`.
# db.create_all() runs inside create_app(), so tables are created on startup.
app = create_app()

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=8000)
