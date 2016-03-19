package com.hexgame;

import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.graphics.g2d.Sprite;

/**
 * Created by Lehel on 3/17/2016.
 */
public class GameObject extends Sprite {

    public final int hexX;
    public final int hexY;
    public final int hexZ;
    public final String identity;
    public boolean clickable=true;

    public GameObject(Texture texture, int gridX, int gridY, int gridZ) {
        super(texture);
        this.hexX = gridX;
        this.hexY = gridY;
        this.hexZ=gridZ;
        //System.out.println("x:" + gridX + " y:" + gridY + " z:" + gridZ);
        this.identity="{y:" + gridY + " z:" + gridZ + " x:" + gridX+"},";
    }



}
