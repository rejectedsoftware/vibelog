vibelog
=======

A fast and simple embeddable blog for multi-site authoring


Embedding VibeLog
-----------------

1. Install [vibe.d](http://github.com/rejectedsoftware/vibe.d) and [MongoDB](http://www.mongodb.org/)

2. Create a new project:

		$ vibe init my-blog
		$ cd my-blog

3. Edit package.json and add the following entry to the "dependencies" section:

		"vibelog": ">=0.0.6"	

4. Edit source/app.d:

	```
	import vibe.d;
	import vibelog.vibelog;

	static this()
	{
		auto router = new UrlRouter;

		auto blogsettings = new VibeLogSettings;
		blogsettings.configName = "vibelog";
		blogsettings.basePath = "/";
		registerVibeLog(blogsettings, router);

		router.get("*", serveStaticFiles("./public"));
		
		auto settings = new HttpServerSettings;
		settings.port = 8080;
		listenHttp(settings, router);
	}
	```

	If you want to run multiple blogs on the same database, you should choose a meaningful configuration name instead of "vibelog". Each blog should have its own configuration name.

5. Start the application (vibe will automatically download vibelog)

		$ vibe

You will probably also want to copy the views/layout.dt file to your own project and modify it to your needs (e.g. by adding a style sheet)


Setting everything up
---------------------

1. Go to the management page on your blog (e.g. <http://127.0.0.1:8080/manage>). Use username `admin` and password `admin` when logging in for the first time.

2. Open the user management page and create a new user. Be sure to make the new user an administrator. The `admin` user will be disaled afterwards.

3. Open the configuration management page and edit the `global` configuration. You should add at least one category here.

4. Now edit the blog's configuration (e.g. `vibelog`) and check all categories that should be listed on the blog.

5. Start posting new articles by choosing `New post` from the management page.