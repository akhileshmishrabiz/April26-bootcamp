from devops_quest import create_app


app = create_app()


if __name__ == "__main__":
    # Training issues: debug mode and binding to every interface.
    app.run(host="0.0.0.0", port=5000, debug=True)
