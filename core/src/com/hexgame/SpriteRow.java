package com.hexgame;

import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.graphics.g2d.Batch;
import com.badlogic.gdx.graphics.g2d.Sprite;

import java.util.ArrayList;
import java.util.List;

/**
 * Created by leheli on 2016.03.14..
 */
public class SpriteRow {

    private List<Sprite> list=new ArrayList<Sprite>();
    private List<Sprite> row2=new ArrayList<Sprite>();
    public  static final float scaleFactor=0.5f;
    public SpriteRow(int nrOfHexes,Texture texture){

            addRow(list,texture,3,0,3);
            addRow(list,texture,4,1,2);
            addRow(list,texture,5,2,1);
            addRow(list,texture,6,3,0);
            addRow(list,texture,5,4,1);
            addRow(list,texture,4,5,2);
            addRow(list,texture,3,6,3);



    }


    private static void addRow(List<Sprite> list ,Texture texture,int nrOfHexes ,int howMany,int paddBy){
        for (int i = 0; i < nrOfHexes; i++) {
            Sprite sprite=new Sprite(texture);
            sprite.scale(-0.5f);
            sprite.setY(howMany*getRow2Y(sprite));
            sprite.setX(paddBy*padding(sprite)+getNextX(i,sprite));
            list.add(sprite);
        }

    }

    private static float getRow2Y(Sprite hex){
        return getScaledHeight(hex)-2-getScaledHeight(hex)/4;
    }

    private static float padding(Sprite hex){
        return (getScaledWidth(hex)-5)/2;
    }

    private static float getNextX(int nr,Sprite hex) {
        float s= nr==0 ? 0 : nr*(getScaledWidth(hex)-5);
        return s;
    }

    private static float getScaledWidth(Sprite hex){
        return  scaleFactor*hex.getWidth();
    }

    private static float getScaledHeight(Sprite hex){
        return  scaleFactor*hex.getHeight();
    }

    public void draw(Batch batch){
        for (Sprite sprite:list) {
            sprite.draw(batch);
        }
    }




}
