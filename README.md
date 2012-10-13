vibelog
=======

Fast and simple embeddable blog for multi-site authoring

Embedding VibeLog
-----------------

1. Install [vibe.d](http://github.com/rejectedsoftware/vibe.d)

2. Create a new project:

		$ vibe init my-blog
		$ cd my-blog

3. Edit package.json and add "vibelog": ">=0.0.6" to the "dependencies" section.

4. Edit source/app.d:

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

5. Start the application

		$ vibe

You will probably also want to copy the views/layout.dt file to your own project and modify it to your needs (e.g. by adding a style sheet)