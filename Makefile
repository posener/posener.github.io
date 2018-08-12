run:
	docker run --rm \
      -v $(PWD):/srv/jekyll \
      -v $(PWD)/.bundle:/usr/local/bundle \
      -p 35729:35729 -p 4000:4000 \
      jekyll/builder:3.8 \
      jekyll serve --watch

exec:
	docker run --rm \
      -v $(PWD):/srv/jekyll \
      -v $(PWD)/.bundle:/usr/local/bundle \
      -it \
      jekyll/builder:3.8 \
      bash
