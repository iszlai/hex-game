package com.hexgame.screens;

import com.badlogic.gdx.Gdx;
import com.badlogic.gdx.Screen;
import com.badlogic.gdx.graphics.GL20;
import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.math.Interpolation;
import com.badlogic.gdx.scenes.scene2d.Action;
import com.badlogic.gdx.scenes.scene2d.Stage;
import com.badlogic.gdx.scenes.scene2d.ui.Image;
import com.badlogic.gdx.utils.viewport.FillViewport;
import com.badlogic.gdx.utils.viewport.FitViewport;
import com.hexgame.Hex;
import static com.badlogic.gdx.scenes.scene2d.actions.Actions.*;


/**
 * Created by leheli on 2016.04.03..
 */
public class SplashScreen implements Screen {

    private final Hex app;
    private final Stage stage;
    private Image splashImage;

    public SplashScreen (final Hex app){
        this.app=app;
        this.stage=new Stage(new FitViewport(Hex.V_WIDTH,Hex.V_HEIGHT,app.camera));
        Gdx.input.setInputProcessor(stage);
        Texture splashTex=new Texture("BLUE.png");
        splashImage=new Image(splashTex);
        splashImage.setOrigin(splashImage.getWidth() / 2, splashImage.getHeight() / 2);
        stage.addActor(splashImage);


    }
    @Override
    public void show() {
        splashImage.setPosition(stage.getWidth() / 2 - 16, stage.getHeight() / 2 + 16);
        splashImage.addAction(sequence(alpha(0f), scaleTo(0.1f, 0.1f),
                parallel(fadeIn(2f, Interpolation.pow2),
                        scaleTo(2f, 2f, 2.5f, Interpolation.pow5),
                        moveTo(stage.getWidth() / 2 - 16, stage.getHeight() / 2 - 16, 2f, Interpolation.swing)), new Action() {
                    @Override
                    public boolean act(float delta) {
                        app.setScreen(new LevelScreen(app,0));
                        return true;
                    }
                }));


    }

    @Override
    public void render(float delta) {
        Gdx.gl.glClearColor(0.81f, 0.85f, 0.86f, 1);
        Gdx.gl.glClear(GL20.GL_COLOR_BUFFER_BIT);
        stage.draw();

        update(delta);
        app.batch.begin();
        app.font.draw(app.batch,"SpashScreen",900,stage.getHeight()/4);
        app.batch.end();
    }

    private void update(float delta) {
        stage.act(delta);
    }

    @Override
    public void resize(int width, int height) {
        stage.getViewport().update(width,height,false);
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
        stage.dispose();
    }
}
