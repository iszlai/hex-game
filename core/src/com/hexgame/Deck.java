package com.hexgame;

import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.graphics.g2d.Sprite;

/**
 * Created by leheli on 2016.03.19..
 */
public class Deck extends Sprite {

public Deck(){
    super(getNextTexture());
}


private static Texture getNextTexture (){
    return new Texture(Utils.randomEnum(Sides.class).textureFile);
}

    public void next(){
        this.setTexture(getNextTexture());
    }




}
