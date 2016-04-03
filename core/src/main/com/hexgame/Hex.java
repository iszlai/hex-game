package com.hexgame;

import com.badlogic.gdx.Game;
import com.badlogic.gdx.Gdx;
import com.badlogic.gdx.assets.AssetManager;
import com.badlogic.gdx.graphics.Color;
import com.badlogic.gdx.graphics.GL20;
import com.badlogic.gdx.graphics.OrthographicCamera;
import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.graphics.g2d.BitmapFont;
import com.badlogic.gdx.graphics.g2d.SpriteBatch;
import com.badlogic.gdx.scenes.scene2d.Stage;
import com.hexgame.screens.LevelScreen;
import com.hexgame.screens.SplashScreen;

public class Hex extends Game {

	public static final float V_WIDTH = 480;
	public static final float V_HEIGHT = 289;
	private Stage stage;
	public SpriteBatch batch;
	public BitmapFont font;
	public OrthographicCamera camera;
	public AssetManager assets;

	@Override
	public void create() {
		assets=new AssetManager();
		camera=new OrthographicCamera();
		camera.setToOrtho(false,1080,1794);
		batch=new SpriteBatch();
		font=new BitmapFont();
		font.setColor(Color.BLACK);
		this.setScreen(new SplashScreen(this));
	}

	@Override
	public void render() {
		super.render();
	}

	@Override
	public void dispose() {
		batch.dispose();
		font.dispose();
		assets.dispose();
		this.getScreen().dispose();

	}
}
