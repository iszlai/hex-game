package com.hexgame.screens;

import com.badlogic.gdx.Application;
import com.badlogic.gdx.Gdx;
import com.badlogic.gdx.Screen;
import com.badlogic.gdx.graphics.Color;
import com.badlogic.gdx.graphics.GL20;
import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.graphics.g2d.SpriteBatch;
import com.badlogic.gdx.utils.Timer;
import com.hexgame.Hex;
import com.hexgame.model.Deck;
import com.hexgame.model.HiveGrid;

/**
 * Created by leheli on 2016.04.03..
 */
public class LevelScreen implements Screen {


    private final Hex app;
    private final SpriteBatch batch;
    private final Texture img;
    private final HiveGrid row;
    private final Deck hex;
    private final int lvl;

    public LevelScreen (final Hex app,int lvl){
        this.app=app;
        this.lvl=lvl;
        batch = new SpriteBatch();
        img = new Texture("hex.png");
        row = new com.hexgame.model.HiveGrid(5, img,lvl);
        hex = new com.hexgame.model.Deck();
        hex.setX(1000);
        //hex.scale(-0.5f);
        System.out.println(Gdx.graphics.getWidth());
        System.out.println(Gdx.graphics.getHeight());

    }


    private void update() {
        if (Gdx.input.justTouched()) {
            float x = Gdx.input.getX();
            float y = Gdx.graphics.getHeight() - Gdx.input.getY();
            for (com.hexgame.model.GameObject sprite : row.list) {
                if (sprite.getBoundingRectangle().contains(x, y)&&sprite.clickable) {
                    sprite.clickable=false;
                    sprite.setColor(Color.RED);
                    sprite.setTexture(hex.getTexture());
                    com.hexgame.model.GridLocation neighbour = sprite.location.getNeighbour(hex.side);
                    com.hexgame.model.GameObject gameObject = row.grid.get(neighbour);
                    if(gameObject!=null) {
                        gameObject.setColor(Color.GREEN);
                        gameObject.walkAble=true;
                    }
                    hex.next();
                    if(com.hexgame.utils.Utils.isGameOver(row.start, row.end)){

                        Timer.schedule(new Timer.Task() {
                            @Override
                            public void run() {
                                app.setScreen(new StarsScreen(app,lvl+1));
                            }
                        },1);


                    }
                }
            }

        }

    }

    @Override
    public void show() {

    }

    @Override
    public void render(float delta) {
        Gdx.gl.glClearColor(0.81f, 0.85f, 0.86f, 1);
        Gdx.gl.glClear(GL20.GL_COLOR_BUFFER_BIT);
        batch.begin();
        row.draw(batch);
        hex.draw(batch);
        batch.end();
        update();
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
        img.dispose();
    }
}
