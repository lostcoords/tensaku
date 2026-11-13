# The changelog page renders ../CHANGELOG.md, outside the docs app, so Tensaku may edit that file.
Tensaku.register_writable_path("../CHANGELOG.md") if Rails.env.development?
