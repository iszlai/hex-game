package com.hexgame;

import com.badlogic.gdx.ApplicationAdapter;
import com.badlogic.gdx.Gdx;
import com.badlogic.gdx.graphics.Color;
import com.badlogic.gdx.graphics.GL20;
import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.graphics.g2d.Sprite;
import com.badlogic.gdx.graphics.g2d.SpriteBatch;

public class Hex extends ApplicationAdapter {
	SpriteBatch batch;
	Texture img;
    SpriteRow row;
	Sprite hex;


	@Override
	public void create () {
		batch = new SpriteBatch();
		img = new Texture("hex.png");
        row=new SpriteRow(5,img);
		hex=new Sprite(img);
		hex.setX(400);
        hex.scale(-0.5f);
		hex.setColor(Color.CORAL);
	}

    @Override
	public void render () {
		Gdx.gl.glClearColor(0.81f, 0.85f, 0.86f, 1);
		Gdx.gl.glClear(GL20.GL_COLOR_BUFFER_BIT);
		batch.begin();
		    row.draw(batch);
			hex.draw(batch);
        batch.end();
	}
}
