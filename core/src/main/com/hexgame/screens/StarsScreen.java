package com.hexgame.screens;

import com.badlogic.gdx.Gdx;
import com.badlogic.gdx.Screen;
import com.badlogic.gdx.graphics.GL20;
import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.graphics.g2d.Sprite;
import com.badlogic.gdx.graphics.g2d.SpriteBatch;
import com.hexgame.Hex;

/**
 * Created by leheli on 2016.04.03..
 */
public class StarsScreen implements Screen {


    private final int currentLevel;
    private final Hex app;
    Sprite star;
    SpriteBatch batch;
    Texture starTexture;

    public StarsScreen(Hex app, int i) {
        this.app=app;
        this.currentLevel=i;
        starTexture=new Texture("star.png");
        star=new Sprite(starTexture);
        star.setX(Gdx.graphics.getWidth()/2);
        star.setY(Gdx.graphics.getHeight()/2);
        batch = new SpriteBatch();
    }

    @Override
    public void show() {

    }

    @Override
    public void render(float delta) {
        Gdx.gl.glClearColor(0.81f, 0.85f, 0.86f, 1);
        Gdx.gl.glClear(GL20.GL_COLOR_BUFFER_BIT);
        batch.begin();
        star.draw(batch);
        batch.end();
        app.batch.begin();
        app.font.draw(app.batch,"Current Level: "+this.currentLevel,Gdx.graphics.getWidth()/2-100,Gdx.graphics.getHeight()/2);
        app.batch.end();
        update(delta);

    }

    private void update(float delta) {
        if (Gdx.input.justTouched()) {
            float x = Gdx.input.getX();
            float y = Gdx.graphics.getHeight() - Gdx.input.getY();

            if(star.getBoundingRectangle().contains(x,y)){
                this.app.setScreen(new LevelScreen(app,currentLevel));
            }
        }
    }

    @Override
    public void resize(int width, int height) {

    }

    @Override
    public void pause() {

    }

    @Override
    public void resume() {

    }

    @Override
    public void hide() {

    }

    @Override
    public void dispose() {
        batch.dispose();
        star.getTexture().dispose();
    }
}
