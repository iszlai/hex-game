package com.hexgame.model;

import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.graphics.g2d.Sprite;
import com.hexgame.utils.Utils;

/**
 * Created by leheli on 2016.03.19..
 */
public class Deck extends Sprite {

public Sides side;
public Deck(){
    super(getNextTexture());
    next();
}


private static Texture getNextTexture (){
    return new Texture(Utils.randomEnum(Sides.class).textureFile);
}

    public void next(){
        this.side=Utils.randomEnum(Sides.class);
        this.setTexture(new Texture(side.textureFile));
    }




}
